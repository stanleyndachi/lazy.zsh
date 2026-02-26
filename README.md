# 💤 lazy.zsh

**lazy.zsh** is a **lightweight and minimal** Zsh plugin manager.

### ✨ Features

- 🚀 **Fast & Lightweight** – No unnecessary dependencies, just pure Zsh and Git.
- ⚡ **One-Line Bootstrap** – Quickly install lazy.zsh by adding a small snippet to `.zshrc`.
- 🛠 **Reproducible Environments** – Easily reproduce the same Zsh setup by using the same `.zshrc`.
- 🌍 **Supports Multiple Sources** – Install plugins using:  
    - Short GitHub URLs (`username/repository`)  
    - Full Git URLs (`https://`, `git@`, etc.)  
    - Local paths
- 📌 **Version Locking** – Supports locking plugins to a specific `branch`, `tag`, or `commit`.
- 🔄 **Automatic Updates** – Set an update interval and get reminders to keep plugins up to date.
- 🔗 **Easy Plugin Management** – Install, update, list, and remove plugins with simple commands.

### ⚡️ Requirements

- zsh
- git

### 📦 Installation

- Add the following code to your `.zshrc`.

    ```sh
    # ----- lazy.zsh configuration: start -----
    # define your plugins here
    declare -a LAZYZ_PLUGINS=(
        # example plugins:
        "https://github.com/stanleyndachi/lazy.zsh"      # Full URL
        "zsh-users/zsh-syntax-highlighting"              # GitHub short URL
        "zsh-users/zsh-autosuggestions"
        # "Aloxaf/fzf-tab"
        # "/home/user/mysecret/plugin local=true"        # Local plugin
    )

    export LAZYZ_DATA_HOME="$HOME/.local/share/zsh/lazyz"  # plugin storage directory
    export LAZYZ_CACHE_HOME="$HOME/.cache/zsh/lazyz"       # plugin cache directory
    export LAZYZ_UPDATE_REMINDER=true                      # enable update reminders
    export LAZYZ_UPDATE_INTERVAL=14                        # update interval (days)

    # bootstrap lazy.zsh
    function .lazyz_bootstrap() {
        if [[ -f "${LAZYZ_DATA_HOME}/lazy.zsh/lazy.zsh" ]]; then
            source "${LAZYZ_DATA_HOME}/lazy.zsh/lazy.zsh"
        elif command -v git &>/dev/null; then
            print "[lazyz]: lazy.zsh not found. Downloading ..."
            rm -rf "${LAZYZ_DATA_HOME}/lazy.zsh" &>/dev/null
            git clone --depth=1 'https://github.com/stanleyndachi/lazy.zsh' "${LAZYZ_DATA_HOME}/lazy.zsh"
            source "${LAZYZ_DATA_HOME}/lazy.zsh/lazy.zsh"
        else
            print "[lazyz]: lazy.zsh couldn't be installed. Please install 'git'"
      fi
    }
    .lazyz_bootstrap
    unset -f .lazyz_bootstrap
    alias zshrc="${EDITOR:-vi} ~/.zshrc"    # Quick access to the ~/.zshrc file
    # ----- lazy.zsh configuration: end -----
    ```

    🔹 **Tip**: Ensure that `compinit` is loaded after `lazy.zsh`.

- Source the `.zshrc` or restart your terminal.

    ```sh
    source ~/.zshrc
    ```

- Run `lazyz help` to see all available commands.

### ⚙️ Configuration

#### Defining Plugins

`lazy.zsh` uses a **flat, declarative string-based configuration**.
Each plugin is defined as a single string inside the `LAZYZ_PLUGINS` array.
The first token specifies the plugin source, while any following `key=value`
pairs act as options that control how the plugin is handled.

```sh
declare -a LAZYZ_PLUGINS=(
    "plugin_url option1=value1 option2=value2 ..."
)
```

Internally, `lazy.zsh` parses these strings into **structured plugin metadata**
using associative arrays, but users only interact with the simple, flat format.
This design avoids complex data structures while remaining expressive and easy
to parse in pure Zsh.

##### Available Plugin Options

| Option    | Description | Required |
|-----------|------------|-----------|
| (implicit) | Plugin source (first token in entry) | ✅ Yes |
| `branch`  | Git branch to checkout | ❌ No |
| `commit`  | Lock plugin to a specific commit | ❌ No |
| `tag`     | Lock plugin to a specific tag | ❌ No |
| `build` | Commands executed in the plugin directory after install or update | ❌ No |
| `local`    | Is a local plugin (`default=false`) | ❌ No |

##### Example Configuration

```sh
declare -a LAZYZ_PLUGINS=(
    # Full URL (latest commit from the default branch)
    "https://github.com/stanleyndachi/lazy.zsh"
    # Lock the plugin to a specific commit
    "Aloxaf/fzf-tab commit=abcd123"
    "zsh-users/zsh-syntax-highlighting branch=develop commit=123abcd"
    # Use a Git tag instead of the latest commit
    "zsh-users/zsh-autosuggestions tag=v0.7.1"
    # Plugin that requires a build step
    "zdharma-continuum/fast-syntax-highlighting build='make && make install' branch=dev"
    # Local plugin
    "/home/user/mysecret/plugin local=true"
)
```

```json
// JSON equivalent
{
    "https://github.com/stanleyndachi/lazy.zsh": {},
    "Aloxaf/fzf-tab": {
        "commit": "abcd123"
    },
    "zsh-users/zsh-syntax-highlighting": {
        "branch": "develop",
        "commit": "123abcd"
    },
    "zsh-users/zsh-autosuggestions": {
        "tag": "v0.7.1"
    },
    "zdharma-continuum/fast-syntax-highlighting": {
        "build": "make && make install",
        "branch": "dev",
    },
    "/home/user/mysecret/plugin": {
        "local": "true"
    },
}
```

#### Other Options
- To get a reminder to update your plugins, set `LAZYZ_UPDATE_REMINDER=true`.
- `LAZYZ_UPDATE_INTERVAL` defines how often (in days) to get a reminder (default: `14` days).
- `LAZYZ_DATA_HOME` defines the directory where plugins will be installed (default: `~/.local/share/zsh/lazyz/`). 
- `LAZYZ_CACHE_HOME` defines the cache directory (default: `~/.cache/zsh/lazyz/`). 

### 🔎 Missing Features

This design keeps `lazy.zsh` **minimal** and **predictable**, avoids implicit
sourcing, and gives users full control over load order and startup
performance. To load plugins, **manually source them** in your `.zshrc`.
For example:

```sh
# Load powerlevel10k theme
source "$LAZYZ_DATA_HOME/powerlevel10k/powerlevel10k.zsh-theme"
```

🔹 **Tip**: Some plugins may have different filenames (e.g., `plugin.zsh`, `init.zsh`). Check the plugin’s documentation for the correct source file.

### ❓ FAQs

#### What is a ghost plugin

Ghost plugin = a directory under `LAZYZ_DATA_HOME` that:
1. Looks like a plugin (git repo or plugin files)
2. Is not represented by any entry in `LAZYZ_PLUGINS`

#### Why does a plugin entry in `LAZYZ_PLUGINS` array have a weird syntax?

Simple! [Zsh shell does not have built-in support for multi-dimmensional array](https://www.zsh.org/mla/users/2016/msg00778.html)

#### Where can I get a starter `.zshrc` file?

A well-structured starter [.zshrc](https://github.com/stanleyndachi/lazy.zsh/blob/main/examples/zshrc) is available in the this repository.

```sh
curl -o ~/.zshrc 'https://raw.githubusercontent.com/stanleyndachi/lazy.zsh/refs/heads/main/examples/zshrc'
```

#### How do I uninstall `lazy.zsh`?

1. Delete the code snippet added during installation from your `.zshrc`.

2. Remove the plugins directory (optional)
   - To remove only `lazy.zsh`:

     ```sh
     rm -rf "${LAZYZ_DATA_HOME}/lazy.zsh"
     ```

   - To remove ALL installed plugins:

     ```sh
     echo "Are you sure you want to delete all plugins? (y/N)"
     read -r confirm
     [[ "$confirm" =~ ^[Yy]$ ]] && rm -rf "${LAZYZ_DATA_HOME}"
     ```

### 📝 TODO

- [ ] [ZSH Plugin Standard](https://zdharma-continuum.github.io/Zsh-100-Commits-Club/Zsh-Plugin-Standard.html)

### 🌐 Other Resources

- [autoupdate-oh-my-zsh-plugins](https://github.com/tamcore/autoupdate-oh-my-zsh-plugins) - oh-my-zsh plugin for auto updating of git-repositories in $ZSH_CUSTOM folder

- [awesome-zsh-plugins](https://github.com/unixorn/awesome-zsh-plugins) - A collection of ZSH frameworks, plugins, tutorials & themes inspired by the various awesome list collections out there.

