#include <openssl/ec.h>
#include <openssl/ecdsa.h>
#include <openssl/nid.h>
#include <openssl/sha.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

int main(void)
{
    static const char message[] = "VKMT Chromium ECDSA translation gate";
    uint8_t digest[SHA256_DIGEST_LENGTH];
    uint8_t signature[256];
    unsigned signature_size = sizeof(signature);
    EC_KEY *key;
    int iteration;

    SHA256((const uint8_t *)message, strlen(message), digest);
    key = EC_KEY_new_by_curve_name(NID_X9_62_prime256v1);
    if (!key || !EC_KEY_generate_key(key))
    {
        fputs("VKMT_BORINGSSL_ECDSA_KEY_FAILED\n", stderr);
        return 2;
    }
    if (!ECDSA_sign(0, digest, sizeof(digest), signature, &signature_size, key))
    {
        fputs("VKMT_BORINGSSL_ECDSA_SIGN_FAILED\n", stderr);
        EC_KEY_free(key);
        return 3;
    }
    for (iteration = 0; iteration != 1000; ++iteration)
    {
        if (ECDSA_verify(0, digest, sizeof(digest), signature, signature_size, key) != 1)
        {
            fprintf(stderr, "VKMT_BORINGSSL_ECDSA_VERIFY_FAILED iteration=%d\n", iteration);
            EC_KEY_free(key);
            return 4;
        }
    }
    EC_KEY_free(key);
    puts("VKMT_BORINGSSL_ECDSA_VERIFY_OK iterations=1000 curve=P-256");
    return 0;
}
