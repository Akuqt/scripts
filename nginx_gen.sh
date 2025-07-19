#!/bin/bash
set -e

# Check if a name is provided
if [[ -z "$1" || -z "$2" || -z "$3" || -z "$4" || -z "$5" || -z "$6" || -z "$7" ]]; then
    echo -e "\nError: Missing required parameters.\n"
    echo -e "Usage:\n\n $0 <NAME> <IP> <SLD> <TLD> <USER> <API_KEY> <EMAIL>\n"
    echo -e "Example:\n\n $0 subdomain example com api_user api_key test@example.com\n"
    exit 1
fi

NAME="$1"
IP="$2"
SLD="$3"
TLD="$4"
USER="$5"
API_KEY="$6"
EMAIL="$7"

URI="api.namecheap.com/xml.response"
GLOBAL_PARAMS="ApiUser=$USER&UserName=$USER&ClientIp=127.0.0.1&SLD=$SLD&TLD=$TLD"
COMMAND="namecheap.domains.dns.getHosts"

echo "Getting subdomains from namecheap hosting..."

res=$(curl -s "https://$URI?ApiKey=$API_KEY&Command=$COMMAND&$GLOBAL_PARAMS")

PARAMS=""
i=1

if echo $res | grep -q "DomainDNSGetHostsResult"; then

    while read line; do
        PARAMS+="HostName$i=$line&RecordType$i=A&Address$i=$IP&"
        i=$((i + 1))
    done < <(echo $res | xq -q 'host' -a 'name')

    PARAMS+="HostName$i=$NAME&RecordType$i=A&Address$i=$IP"

else
    echo "Invalid query..."
    exit 1

fi

echo "Creating new subdomain '$NAME' in namecheap hosting..."

COMMAND="namecheap.domains.dns.setHosts"

res=$(curl -s "https://$URI?ApiKey=$API_KEY&Command=$COMMAND&$GLOBAL_PARAMS&$PARAMS")

if echo $res | grep -q "DomainDNSSetHostsResult"; then

    success=$(echo $res | xq -q 'DomainDNSSetHostsResult' -a 'issuccess')

    if "$success" == "true"; then
        echo "Subdomain $NAME added successfully, see subdomain list below:"

        COMMAND="namecheap.domains.dns.getHosts"

        res=$(curl -s "https://$URI?ApiKey=$API_KEY&Command=$COMMAND&$GLOBAL_PARAMS")

        i=1

        if echo $res | grep -q "DomainDNSGetHostsResult"; then

            while read line; do
                echo "Subdomain$i: $line"
                i=$((i + 1))
            done < <(echo $res | xq -q 'host' -a 'name')

        else
            echo "Invalid query..."
            exit 1

        fi

    fi

else
    echo "Invalid query..."
    exit 1
fi

# Create the directory
mkdir -p /var/www/$NAME/html

# Provide feedback
echo "Directory /var/www/$NAME/html created successfully."

# Create an HTML file
cat <<EOF >/var/www/$NAME/html/index.html
<!DOCTYPE html>
<html>
<head>
<title>Welcome to $NAME.$SLD.$TLD!</title>
<style>
    body {
        width: 35em;
        margin: 0 auto;
        font-family: Tahoma, Verdana, Arial, sans-serif;
    }
</style>
</head>
<body>
<h1>Welcome to $NAME.$SLD.$TLD!</h1>
<p>If you see this page, the $NAME.$SLD.$TLD endpoint is ready...</p>

<p><em>$SLD.$TLD hosting domain...</em></p>
</body>
</html>

EOF

# Provide feedback
echo "HTML file /var/www/$NAME/html/index.html was created successfully."

# Create the Nginx configuration file
cat <<EOL >/etc/nginx/sites-available/$NAME.$SLD.$TLD
server {
    listen 80;
    server_name $NAME.$SLD.$TLD;

    root /var/www/$NAME/html;
    index index.html;

    location / {
        try_files \$uri \$uri/ =404;
    }
}
EOL

# Provide feedback
echo "Nginx configuration file /etc/nginx/sites-available/$NAME.$SLD.$TLD created successfully."

# Create a symbolic link
ln -s /etc/nginx/sites-available/$NAME.$SLD.$TLD /etc/nginx/sites-enabled/

# Provide feedback
echo "Symbolic link for /etc/nginx/sites-available/$NAME.$SLD.$TLD created in /etc/nginx/sites-enabled/."

echo "Waiting for DNS timeout (5s)..."

sleep 5

# Restart NGINX
echo "Restarting NGINX"

systemctl restart nginx.service

echo "Waiting for PROXY timeout (5s)..."

sleep 5

echo "Getting SSL Certificate"

# Obtain SSL certificate using Certbot
certbot --nginx -d $NAME.$SLD.$TLD --non-interactive --agree-tos -m $EMAIL

# Provide feedback
echo "SSL certificate for $NAME.$SLD.$TLD obtained successfully."

# Restart NGINX
echo "Restarting NGINX to apply SSL Certificate"

systemctl restart nginx.service

echo "Restarting NGINX to apply SSL Certificate"

echo "Subdomain $NAME.$SLD.$TLD is ready to use with SSL enabled."
