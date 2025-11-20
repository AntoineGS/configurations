# Teams for Linux Configuration

## Setup

The `config.json` file contains sensitive credentials and is **not tracked in git**. Instead, we use a template-based approach:

1. **Create your local secrets file:**
   ```bash
   cp ~/.config/zsh/.zshenv.local.example ~/.config/zsh/.zshenv.local
   ```

2. **Edit `.zshenv.local` and add your password:**
   ```bash
   export TEAMS_MQTT_PASSWORD="your-actual-password"
   ```

3. **Generate the config file:**
   ```bash
   ./generate-config.sh
   ```

The script will read the environment variables from `.zshenv.local` and generate `config.json` from the template.

## Files

- `config.json.template` - Template with `${VARIABLE}` placeholders (tracked in git)
- `config.json` - Generated config with actual secrets (ignored by git)
- `generate-config.sh` - Script to generate config from template
- `~/.config/zsh/.zshenv.local` - Your local secrets (ignored by git)
- `~/.config/zsh/.zshenv.local.example` - Example secrets file (tracked in git)
