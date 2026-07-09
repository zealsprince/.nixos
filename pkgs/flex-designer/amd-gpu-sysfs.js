
// Appended by the flex-designer nix package. systeminformation only fills
// utilizationGpu and friends from nvidia-smi, so AMD cards always show N/A.
// This merges amdgpu sysfs metrics into the controller, matched by PCI bus
// address. Called from the Linux branch of graphics() above.
function mergeControllerAmdSysfs(controller) {
  try {
    if (!controller.busAddress) { return controller; }
    const drm = '/sys/class/drm';
    const readNum = (p) => {
      try { return parseInt(fs.readFileSync(p, 'utf8').trim(), 10); } catch (e) { return null; }
    };
    const cards = fs.readdirSync(drm).filter((f) => /^card[0-9]+$/.test(f));
    for (const card of cards) {
      const dev = drm + '/' + card + '/device';
      let slot = '';
      try {
        const uevent = fs.readFileSync(dev + '/uevent', 'utf8');
        const match = uevent.match(/PCI_SLOT_NAME=(\S+)/);
        slot = match ? match[1].toLowerCase() : '';
      } catch (e) { continue; }
      if (!slot || !slot.endsWith(controller.busAddress.toLowerCase())) { continue; }
      let pciVendor = '';
      try { pciVendor = fs.readFileSync(dev + '/vendor', 'utf8').trim(); } catch (e) { util.noop(); }
      if (pciVendor !== '0x1002') { return controller; }
      const busy = readNum(dev + '/gpu_busy_percent');
      if (busy !== null) { controller.utilizationGpu = busy; }
      const vramUsed = readNum(dev + '/mem_info_vram_used');
      const vramTotal = readNum(dev + '/mem_info_vram_total');
      if (vramTotal) {
        controller.vram = Math.round(vramTotal / 1024 / 1024);
        controller.memoryTotal = controller.vram;
      }
      if (vramUsed !== null) {
        controller.memoryUsed = Math.round(vramUsed / 1024 / 1024);
        if (vramTotal) {
          controller.memoryFree = Math.round((vramTotal - vramUsed) / 1024 / 1024);
          controller.utilizationMemory = Math.round((vramUsed / vramTotal) * 100);
        }
      }
      let hwmons = [];
      try { hwmons = fs.readdirSync(dev + '/hwmon'); } catch (e) { util.noop(); }
      for (const hw of hwmons) {
        const hwPath = dev + '/hwmon/' + hw;
        const temp = readNum(hwPath + '/temp1_input');
        if (temp !== null) { controller.temperatureGpu = Math.round(temp / 1000); }
        const power = readNum(hwPath + '/power1_average');
        if (power !== null) { controller.powerDraw = Math.round(power / 1000) / 1000; }
        const fan = readNum(hwPath + '/fan1_input');
        if (fan !== null) { controller.fanSpeed = fan; }
        const clockCore = readNum(hwPath + '/freq1_input');
        if (clockCore !== null) { controller.clockCore = Math.round(clockCore / 1000000); }
        const clockMem = readNum(hwPath + '/freq2_input');
        if (clockMem !== null) { controller.clockMemory = Math.round(clockMem / 1000000); }
      }
      break;
    }
  } catch (e) {
    util.noop();
  }
  return controller;
}
