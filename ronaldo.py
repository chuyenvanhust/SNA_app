# pip install python-jose cryptography


from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import rsa, ec, ed25519
from jose import jwt
from jose.constants import ALGORITHMS
from typing import Tuple, Any, Optional
from datetime import datetime, timedelta
from jose import jwt


def get_algorithm_from_private_key(private_key: Any) -> str:
    if isinstance(private_key, rsa.RSAPrivateNumbers) or isinstance(
        private_key, rsa.RSAPrivateKey
    ):
        key_size = private_key.key_size
        if key_size == 2048:
            return ALGORITHMS.RS256
        elif key_size == 3072:
            return ALGORITHMS.RS384
        elif key_size == 4096:
            return ALGORITHMS.RS512
        else:
            return ALGORITHMS.RS256
    elif isinstance(private_key, ec.EllipticCurvePrivateNumbers) or isinstance(
        private_key, ec.EllipticCurvePrivateKey
    ):
        curve_name = private_key.curve.name
        if curve_name == "secp256r1":
            return ALGORITHMS.ES256
        elif curve_name == "secp384r1":
            return ALGORITHMS.ES384
        elif curve_name == "secp521r1":
            return ALGORITHMS.ES512
        else:
            raise ValueError(f"Unsupported ECDSA curve: {curve_name}")
    elif isinstance(private_key, ed25519.Ed25519PrivateKey):
        raise ValueError(f"Unsupported EdDSA curve: {curve_name}")

    raise TypeError("Unsupported private key type for JOSE signing.")


def load_private_key_from_pem(pem_key_string: str) -> Tuple[Any, str]:
    #private_key_bytes = pem_key_string.encode("utf-8")
    private_key_bytes = pem_key_string #because read from file
    try:
        private_key = serialization.load_pem_private_key(
            private_key_bytes, password=None
        )
        algorithm = get_algorithm_from_private_key(private_key)
        return private_key, algorithm
    except Exception as e:
        try:
            private_key = serialization.load_pem_private_key(
                private_key_bytes, password=None
            )
            algorithm = get_algorithm_from_private_key(private_key)
            return private_key, algorithm
        except Exception as e_pkcs1:
            raise ValueError(
                f"Failed to parse private key from PEM string. PKCS#8 error: {e}, PKCS#1 error: {e_pkcs1}"
            )


def sign_jar_request(
    client_id: str,
    audience: str,
    scopes: list[str],
    redirect_uri: str,
    private_key_pem: str,
    state: str = "",
):
    try:
        private_key, algorithm = load_private_key_from_pem(private_key_pem)
    except ValueError as e:
        print(f"Error PEM: {e}")
        return None, e
    now = datetime.now()
    claims = {
        "iss": client_id,  # Issuer MUST be client_id
        "aud": audience,  # Audience MUST be Token Endpoint
        "sub": client_id,  # Subject MUST be client_id
        "exp": int((now + timedelta(seconds=300)).timestamp()),
        "jti": str(int(now.timestamp() * 1000000)),
        "client_id": client_id,
        "response_type": "code",
        "scope": " ".join(scopes),
        "redirect_uri": redirect_uri,
        "state": state,
        "nbf" : int(now.timestamp() * 1000000),
    }
    try:
        request_jwt = jwt.encode(
            claims,
            key=private_key,
            algorithm="RS256",
            
            headers={
                "kid": "gsma-cert-kid"
            }
        )
        return request_jwt, None
    except Exception as err:
        print(f"Error sign JWT: {err}")
        return None, err


def create_client_assertion_jwt(
    client_id: str,
    audience: str,
    private_key_pem: str,
) -> Tuple[Optional[str], Optional[Exception]]:
    try:
        private_key, algorithm = load_private_key_from_pem(private_key_pem)
    except ValueError as e:
        return None, e
    iat = datetime.now()
    exp = iat + timedelta(seconds=300)
    # claims = {
    #     "iss": client_id,  # Issuer MUST be client_id
    #     "sub": client_id,  # Subject MUST be client_id
    #     "aud": audience,  # Audience MUST be Token Endpoint URL
    #     "exp": int(exp.timestamp()),
    #     "iat": int(iat.timestamp()),
    #     "jti": str(int(iat.timestamp() * 1000000)),
    # }
    claims = {
        "iss": client_id,  # Issuer MUST be client_id
        "sub": client_id,  # Subject MUST be client_id
        "aud": "https://developers-access.viettel.vn/security-domain/oauth/token",  # Audience MUST be Token Endpoint URL
        "exp": int(exp.timestamp()),
        "iat": int(iat.timestamp()),
        "jti": str(int(iat.timestamp() * 1000000)),
    }
    try:
        assertion_jwt = jwt.encode(
            claims,
            key=private_key,
            algorithm="RS256",
            headers={
               "kid": "gsma-cert-kid",
               "typ": "JWT"
            }
        )
        return assertion_jwt, None
    except Exception as err:
        return None, err


if __name__ == "__main__":
    with open("./assets/keys/private_key_2.pem", "rb") as key_file:
        private_key_pem = key_file.read()
    
    #private_key_pem = """-----BEGIN PRIVATE KEY-----
#-----END PRIVATE KEY-----
#"""
    print("jar")
    print(
        sign_jar_request(
            #client_id="04176c5e-7436-4057-9850-ad3e0f00bb2d", # VTT application
            #client_id="9a8e04ca-70fe-442c-8438-f1691dd34d3b", # VTT Tammi
            client_id="UhsOT9JBoz2TJxeSwHDqNNDCgot7Nhyhbi5m3-no3P8", 
            audience="https://developers-private.viettel.vn/security-domain",
            redirect_uri="https://google.com",
            scopes=["openid dpv:FraudPreventionAndDetection number-verification:verify number-verification:device-phone-number"],
            state="1",
            private_key_pem=private_key_pem,
        )
    )
    print("\n")
    print("assertion")
    print(
            create_client_assertion_jwt(
                # client_id="04176c5e-7436-4057-9850-ad3e0f00bb2d",
                # client_id="9a8e04ca-70fe-442c-8438-f1691dd34d3b", # VTT Tammi
                # client_id="9a8e04ca-70fe-442c-8438-f1691dd34d3b",
                client_id="UhsOT9JBoz2TJxeSwHDqNNDCgot7Nhyhbi5m3-no3P8",
                audience="https://developers-access.viettel.vn/security-domain/oauth/token",
                private_key_pem=private_key_pem,
            )
    )

#https://afs-publicpoc.viettelsecurity.com/identity-api/oauth/token
