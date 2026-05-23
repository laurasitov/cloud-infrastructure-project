#!/bin/bash

# Exit immediately if any command fails
set -e

echo "=========================================="
echo " Launching Cloud Infrastructure Setup    "
echo "=========================================="

# 1. Repair any interrupted dpkg state and clean up apt
echo "Repairing package manager state..."
sudo dpkg --configure -a
sudo apt --fix-broken install -y
sudo rm -f /var/lib/dpkg/lock-frontend
sudo rm -f /var/lib/dpkg/lock
sudo rm -f /var/cache/apt/archives/lock
sudo dpkg --configure -a

# Update system software lists
sudo apt update

# 2. Install Nginx (Reverse Proxy)
sudo apt install nginx -y

# 3. Add HashiCorp Repository & Install Vault (Secret Manager)
sudo apt-get install -y apt-transport-https software-properties-common wget
wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt update && sudo apt install vault -y

# 4. Start Vault in Dev Mode with an explicit Root Token
sudo systemctl stop vault 2>/dev/null || true
vault server -dev -dev-root-token-id="root" > /tmp/vault.log 2>&1 &

# Wait for Vault to be ready (poll instead of fixed sleep)
echo "Waiting for Vault to become ready..."
export VAULT_ADDR='http://127.0.0.1:8200'
for i in $(seq 1 15); do
    if vault status > /dev/null 2>&1; then
        echo "Vault is up."
        break
    fi
    if [ "$i" -eq 15 ]; then
        echo "ERROR: Vault did not start in time. Check /tmp/vault.log"
        exit 1
    fi
    sleep 1
done

DYNAMIC_TOKEN="root"
echo "Captured Active Vault Token: $DYNAMIC_TOKEN"

# 5. Authenticate with Vault and inject our secret key
vault login "$DYNAMIC_TOKEN"
vault kv put secret/examapp cloud-vault-secret="CloudExamSuccess100!"

# 6. Install Python and pip only, then install Flask and hvac via pip
sudo apt install python3 python3-pip -y
pip3 install flask hvac --break-system-packages

# 7. Write the Python Web Application file using the dynamic token variable
cat << EOF > app.py
from flask import Flask
import hvac

app = Flask(__name__)
vault_client = hvac.Client(url='http://127.0.0.1:8200', token='${DYNAMIC_TOKEN}')

@app.route('/')
def home():
    try:
        read_response = vault_client.secrets.kv.v2.read_secret_version(path='examapp')
        secret_value = read_response['data']['data']['cloud-vault-secret']
        return f"<h1>Cloud Backend Project</h1><p><b>Status:</b> HashiCorp Vault connected successfully.</p><p><b>Decrypted Secret:</b> <span style='color: blue;'>{secret_value}</span></p>"
    except Exception as e:
        return f"<h1>Error fetching secret</h1><p>{str(e)}</p>"

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=5000)
EOF

# 8. Start the Web Application in the background
sudo pkill -f app.py 2>/dev/null || true
python3 app.py &

# Give Flask a moment to bind to port 5000
sleep 2

# 9. Install Prometheus & Grafana (Monitoring Stack)
sudo apt install prometheus -y
sudo mkdir -p /etc/apt/keyrings
wget -q -O - https://apt.grafana.com/gpg.key | gpg --dearmor | sudo tee /etc/apt/keyrings/grafana.gpg > /dev/null
echo "deb [signed-by=/etc/apt/keyrings/grafana.gpg] https://apt.grafana.com stable main" | sudo tee /etc/apt/sources.list.d/grafana.list
sudo apt update && sudo apt install grafana -y
sudo systemctl enable --now prometheus grafana-server

# 10. Configure Grafana to use the /dashboard/ base path
cat << 'EOF' > /etc/grafana/grafana.ini
[server]
domain = localhost
http_port = 3000
root_url = http://localhost/dashboard/
serve_from_sub_path = true
EOF
sudo systemctl restart grafana-server

# 11. Overwrite Nginx configuration rules with our optimised routing
cat << 'EOF' > /etc/nginx/sites-available/default
server {
    listen 80 default_server;
    listen [::]:80 default_server;

    root /var/www/html;
    index index.html index.htm index.nginx-debian.html;
    server_name _;

    location /dashboard/ {
        proxy_pass http://127.0.0.1:3000/dashboard/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    location / {
        proxy_pass http://127.0.0.1:5000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }
}
EOF

# Validate nginx config before restarting
sudo nginx -t

# 12. Restart Nginx to finalise deployment
sudo systemctl restart nginx

echo "=========================================="
echo " Installation Completed Successfully!     "
echo "=========================================="
echo ""
echo " Flask App:  http://localhost:8080"
echo " Grafana:    http://localhost:8080/dashboard/login"
echo " Vault UI:   http://localhost:8200/ui"
echo "=========================================="