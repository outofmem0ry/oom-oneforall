#!/bin/bash

# Usage: ./gencert.sh <FQDN>
# Example: ./gencert.sh harbor.outofmemory.info

# Ensure OpenSSL is installed
if ! command -v openssl &> /dev/null
then
    echo "OpenSSL is not installed. Please install it and try again."
    exit 1
fi

# Check if an FQDN is provided
if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <FQDN>"
    exit 1
fi

FQDN=$1

# Generate a config file for the custom certificate's extensions
cat > custom_cert.cnf <<EOL
[ req ]
distinguished_name = req_distinguished_name
req_extensions     = req_ext

[ req_distinguished_name ]
commonName = Common Name (eg, YOUR name)
commonName_default = $FQDN

[ req_ext ]
subjectAltName = @alt_names

[alt_names]
DNS.1 = $FQDN
EOL

# Step 1: Generate Private Key for the CA
openssl genpkey -algorithm RSA -out ca_private_key.pem

# Step 2: Create a Self-Signed Root Certificate for the CA
openssl req -new -x509 -days 3650 -key ca_private_key.pem -out ca_root_certificate.crt -subj "/C=US/ST=California/L=Palo Alto/O=OOM/OU=oomou/CN=ca"

# Step 3: Generate Private Key for the Custom Certificate
openssl genpkey -algorithm RSA -out custom_private_key.pem

# Step 4: Generate CSR (Certificate Signing Request) for the Custom Certificate
openssl req -new -key custom_private_key.pem -out custom_csr.pem -subj "/C=US/ST=California/L=Palo Alto/O=OOM/OU=oomou/CN=$FQDN" -config custom_cert.cnf

# Step 5: Sign the Custom Certificate with CA's Private Key
openssl x509 -days 3650 -req -in custom_csr.pem -CA ca_root_certificate.crt -CAkey ca_private_key.pem -CAcreateserial -out custom_certificate.crt -extensions req_ext -extfile custom_cert.cnf

echo "Successfully generated custom certificate for $FQDN signed by the private CA."

# Clean up
rm custom_cert.cnf
