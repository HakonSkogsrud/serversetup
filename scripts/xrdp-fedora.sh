sudo dnf install xrdp -y 
sudo systemctl enable xrdp 
sudo systemctl start xrdp 
sudo firewall-cmd --permanent --add-port=3389/tcp 
sudo firewall-cmd --reload 
sudo chcon --type=bin_t /usr/sbin/xrdp 
sudo chcon --type=bin_t /usr/sbin/xrdp-sesman 