#include <openssl/evp.h>
#include <openssl/x509.h>

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

static uint8_t *read_file(const char *path, size_t *size)
{
    FILE *file = fopen(path, "rb");
    uint8_t *data;
    long length;
    if (!file || fseek(file, 0, SEEK_END) || (length = ftell(file)) <= 0 ||
        fseek(file, 0, SEEK_SET))
    {
        if (file) fclose(file);
        return NULL;
    }
    data = malloc((size_t)length);
    if (!data || fread(data, 1, (size_t)length, file) != (size_t)length)
    {
        free(data);
        data = NULL;
    }
    fclose(file);
    *size = (size_t)length;
    return data;
}

int main(int argc, char **argv)
{
    const uint8_t *cursor;
    uint8_t *encoded;
    EVP_PKEY *key;
    X509 *certificate;
    size_t encoded_size;
    int iteration;

    if (argc != 2 || !(encoded = read_file(argv[1], &encoded_size)))
    {
        fputs("VKMT_BORINGSSL_X509_FAILED stage=read\n", stderr);
        return 2;
    }
    cursor = encoded;
    certificate = d2i_X509(NULL, &cursor, encoded_size);
    free(encoded);
    key = certificate ? X509_get_pubkey(certificate) : NULL;
    if (!certificate || !key)
    {
        fputs("VKMT_BORINGSSL_X509_FAILED stage=parse\n", stderr);
        if (certificate) X509_free(certificate);
        return 3;
    }
    for (iteration = 0; iteration != 1000; ++iteration)
    {
        if (X509_verify(certificate, key) != 1)
        {
            fprintf(stderr, "VKMT_BORINGSSL_X509_FAILED stage=verify iteration=%d\n", iteration);
            EVP_PKEY_free(key);
            X509_free(certificate);
            return 4;
        }
    }
    EVP_PKEY_free(key);
    X509_free(certificate);
    puts("VKMT_BORINGSSL_X509_OK iterations=1000");
    return 0;
}
