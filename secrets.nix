let
  # ----------------------------------------------------------------------------
  # Recipients (public keys)
  #
  # agenix can encrypt to:
  # - SSH public keys (ssh-ed25519 / ssh-rsa / etc.)
  # - age recipients (age1...)
  #
  # Best practice:
  # - include the *host* SSH key so the machine can decrypt during activation
  # - include one (or more) admin/user keys so you can edit/re-encrypt off-box
  #
  # These are filled in with real public keys.
  # ----------------------------------------------------------------------------

  # User/admin SSH key (passphrase-protected is fine; mainly for editing/re-encrypting)
  zealsprince = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPrlNjNTTGVZpmLtsfCnYcjW5fcspbPIDsRVXTPHXMtM zealsprince";

  # Example (this machine's host key):
  andrew-dreamreaper = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHaYgXOagy0ccreHCp594ximYRulEr6XzbouLvHSM1fz root@ANDREW-DREAMREAPER";

  # Convenience groups
  admins = [ zealsprince ];
  hosts = [ andrew-dreamreaper ];

  # For local use you typically want both:
  crushRecipients = admins ++ hosts;
in
{
  # ----------------------------------------------------------------------------
  # Crush: OpenAI API Key
  #
  # Encrypted file path (relative to this repo):
  #   .nixos/secrets/crush-openai-api-key.age
  #
  # Decrypted runtime path is controlled by the agenix module; in Home Manager
  # you'll reference `config.age.secrets."<name>".path`.
  # ----------------------------------------------------------------------------
  "secrets/crush-openai-api-key.age".publicKeys = crushRecipients;

  # ----------------------------------------------------------------------------
  # Crush: Gemini API Key
  #
  # Encrypted file path:
  #   .nixos/secrets/crush-gemini-api-key.age
  # ----------------------------------------------------------------------------
  "secrets/crush-gemini-api-key.age".publicKeys = crushRecipients;
}
