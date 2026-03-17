#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# Self-signed CA + Server certificate generator
# Based on Ansible community.crypto module logic
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# --- Usage -------------------------------------------------------------------
usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Generate a self-signed Root CA and a server certificate signed by it.

Options:
  -p, --passphrase PASSPHRASE   CA private key passphrase       (default: changeme)
  -c, --ca-cn COMMON_NAME       Root CA Common Name              (default: Local Dev Root CA)
  -n, --cert-name NAME          Server certificate name          (default: localhost)
  -d, --days DAYS               Server certificate validity days (default: 365)
  -s, --san SAN                 Subject Alternative Name entry.
                                 Can be specified multiple times.
                                 Format: DNS:example.com or IP:1.2.3.4
                                 (default: DNS:localhost,DNS:*.localtest.me,IP:127.0.0.1,IP:::1)
  -o, --output-dir DIR          Output directory for certificates (default: <project>/certs)
  -h, --help                    Show this help message and exit

Environment variables (overridden by CLI arguments):
  CA_PASSPHRASE, ROOT_CA_COMMON_NAME, CERT_NAME, CERT_DAYS, CERT_OUTPUT_DIR

Examples:
  $(basename "$0")
  $(basename "$0") -p mysecret -n myhost -s DNS:myhost -s DNS:*.myhost -s IP:10.0.0.1
  $(basename "$0") --passphrase mysecret --ca-cn "My Root CA" --days 730
EOF
  exit 0
}

# --- Defaults (environment variables as fallback) ----------------------------
CA_PASSPHRASE="${CA_PASSPHRASE:-changeme}"
ROOT_CA_COMMON_NAME="${ROOT_CA_COMMON_NAME:-Local Dev Root CA}"
CERT_NAME="${CERT_NAME:-localhost}"
CERT_DAYS="${CERT_DAYS:-365}"
CERT_DIR="${CERT_OUTPUT_DIR:-${PROJECT_DIR}/certs}"
CERT_SANS=()

# --- Parse arguments ---------------------------------------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    -p|--passphrase)
      CA_PASSPHRASE="$2"; shift 2 ;;
    -c|--ca-cn)
      ROOT_CA_COMMON_NAME="$2"; shift 2 ;;
    -n|--cert-name)
      CERT_NAME="$2"; shift 2 ;;
    -d|--days)
      CERT_DAYS="$2"; shift 2 ;;
    -s|--san)
      CERT_SANS+=("$2"); shift 2 ;;
    -o|--output-dir)
      CERT_DIR="$2"; shift 2 ;;
    -h|--help)
      usage ;;
    *)
      echo "Error: Unknown option: $1" >&2
      echo "Run '$(basename "$0") --help' for usage." >&2
      exit 1 ;;
  esac
done

# If no SANs provided via arguments, use defaults
if [[ ${#CERT_SANS[@]} -eq 0 ]]; then
  CERT_SANS=(
    "DNS:localhost"
    "DNS:*.localtest.me"
    "IP:127.0.0.1"
    "IP:::1"
  )
fi

# --- Directories -------------------------------------------------------------
ROOT_CA_DIR="${CERT_DIR}/ca"
SERVER_DIR="${CERT_DIR}"

mkdir -p "${ROOT_CA_DIR}" "${SERVER_DIR}"

# =============================================================================
# 1. Root CA
# =============================================================================

echo "==> Creating Root CA private key (password-protected)..."
openssl genpkey \
  -algorithm RSA \
  -pkeyopt rsa_keygen_bits:4096 \
  -aes256 \
  -pass "pass:${CA_PASSPHRASE}" \
  -out "${ROOT_CA_DIR}/root.key"

echo "==> Creating Root CA CSR..."
openssl req -new \
  -key "${ROOT_CA_DIR}/root.key" \
  -passin "pass:${CA_PASSPHRASE}" \
  -subj "/CN=${ROOT_CA_COMMON_NAME}" \
  -addext "basicConstraints=critical,CA:TRUE" \
  -addext "keyUsage=critical,cRLSign,keyCertSign" \
  -addext "subjectAltName=DNS:*.localtest.me" \
  -out "${ROOT_CA_DIR}/root.csr"

echo "==> Signing Root CA certificate (self-signed)..."
openssl x509 -req \
  -in "${ROOT_CA_DIR}/root.csr" \
  -signkey "${ROOT_CA_DIR}/root.key" \
  -passin "pass:${CA_PASSPHRASE}" \
  -days 3650 \
  -copy_extensions copyall \
  -out "${ROOT_CA_DIR}/root.pem"

echo "    Root CA created: ${ROOT_CA_DIR}/root.pem"

# =============================================================================
# 2. Server certificate signed by the Root CA
# =============================================================================

# Build SAN string for openssl (e.g. "DNS:localhost,DNS:*.localtest.me,IP:127.0.0.1")
SAN_STRING=$(IFS=','; echo "${CERT_SANS[*]}")

echo "==> Creating server private key..."
openssl genpkey \
  -algorithm RSA \
  -pkeyopt rsa_keygen_bits:2048 \
  -out "${SERVER_DIR}/${CERT_NAME}-key.pem"

echo "==> Creating server CSR..."
openssl req -new \
  -key "${SERVER_DIR}/${CERT_NAME}-key.pem" \
  -subj "/CN=${CERT_NAME}" \
  -addext "basicConstraints=critical,CA:FALSE" \
  -addext "keyUsage=critical,digitalSignature,nonRepudiation,keyEncipherment,dataEncipherment" \
  -addext "subjectAltName=${SAN_STRING}" \
  -out "${SERVER_DIR}/${CERT_NAME}.csr"

echo "==> Signing server certificate with Root CA..."
openssl x509 -req \
  -in "${SERVER_DIR}/${CERT_NAME}.csr" \
  -CA "${ROOT_CA_DIR}/root.pem" \
  -CAkey "${ROOT_CA_DIR}/root.key" \
  -passin "pass:${CA_PASSPHRASE}" \
  -CAcreateserial \
  -days "${CERT_DAYS}" \
  -copy_extensions copyall \
  -out "${SERVER_DIR}/${CERT_NAME}.pem"

echo "    Server cert created: ${SERVER_DIR}/${CERT_NAME}.pem"

# =============================================================================
# 3. Verification
# =============================================================================

echo ""
echo "==> Verifying certificate chain..."
openssl verify -CAfile "${ROOT_CA_DIR}/root.pem" "${SERVER_DIR}/${CERT_NAME}.pem"

echo ""
echo "==> Server certificate details:"
openssl x509 -in "${SERVER_DIR}/${CERT_NAME}.pem" -noout -subject -issuer -dates -ext subjectAltName

echo ""
echo "============================================="
echo "  Done! Files generated:"
echo "    CA cert:     ${ROOT_CA_DIR}/root.pem"
echo "    CA key:      ${ROOT_CA_DIR}/root.key"
echo "    Server cert: ${SERVER_DIR}/${CERT_NAME}.pem"
echo "    Server key:  ${SERVER_DIR}/${CERT_NAME}-key.pem"
echo ""
echo "  To trust the CA on your system:"
echo "    - Windows: Import ${ROOT_CA_DIR}/root.pem into"
echo "              'Trusted Root Certification Authorities'"
echo "    - macOS:   sudo security add-trusted-cert -d -r trustRoot \\"
echo "                -k /Library/Keychains/System.keychain ${ROOT_CA_DIR}/root.pem"
echo "    - Linux:   sudo cp ${ROOT_CA_DIR}/root.pem /usr/local/share/ca-certificates/local-root-ca.crt"
echo "              sudo update-ca-certificates"
echo "============================================="
