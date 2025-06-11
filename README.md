# linux-setup
My Personal Linux Distro setup

### Install
```sh
curl -fsSL https://raw.githubusercontent.com/comchienlab/linux-setup/main/install.sh | bash
```

### After install Linux Distro, can use this script to:
- install Quick Setup script as `qksetup` command
```sh
sudo curl -fsSL -o /usr/local/bin/qksetup https://raw.githubusercontent.com/comchienlab/linux-setup/main/qksetup.sh
sudo chmod +x /usr/local/bin/qksetup
```

- install Quick Git script as `qkgit` command
```sh
sudo curl -fsSL -o /usr/local/bin/qkgit https://raw.githubusercontent.com/comchienlab/linux-setup/main/qkgit.sh
sudo chmod +x /usr/local/bin/qkgit
```

- install Quick Git script as `qkcommit` command
```sh
sudo curl -fsSL -o /usr/local/bin/qkcommit https://raw.githubusercontent.com/comchienlab/linux-setup/main/qkcommit.sh
sudo chmod +x /usr/local/bin/qkcommit
```

- Install n8n
```sh
sudo curl -fsSL -o /usr/local/bin/n8n https://raw.githubusercontent.com/comchienlab/dotfiles/main/n8n/n8n-installer.sh
sudo chmod +x /usr/local/bin/n8n
```
Or
```
bash <(curl -fsSL https://raw.githubusercontent.com/comchienlab/dotfiles/main/n8n/n8n-installer.sh)
```

- Install rclone tool
```sh
sudo curl -fsSL -o /usr/local/bin/cccrclone https://raw.githubusercontent.com/comchienlab/dotfiles/main/rclone/rclone-tool.sh
sudo chmod +x /usr/local/bin/cccrclone
```

- Install Nerd font installer
```sh
bash <(curl -fsSL https://raw.githubusercontent.com/comchienlab/dotfiles/main/fonts/nerdfont-installer.sh)
```

- Create swap file
```sh
bash <(curl -fsSL https://raw.githubusercontent.com/comchienlab/dotfiles/main/create_swap.sh)
```

- Install Quick Macos
```sh
sudo curl -fsSL -o /usr/local/bin/qkmacos https://raw.githubusercontent.com/comchienlab/dotfiles/main/macos/qkmacos.sh
sudo chmod +x /usr/local/bin/qkmacos
```
