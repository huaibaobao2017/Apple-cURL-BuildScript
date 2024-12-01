# Apple-cURL-BuildScript

Script for building cURL for Apple platforms (iOS, iOS Simulator, tvOS, tvOS Simulator, macOS)

## Details

- iOS: arm64
- iOS Simulator: arm64, x86_64
- macOS: x86_64, arm64
- tvOS: arm64
- tvOS Simulator: arm64, x86_64

## Usage

```bash
$ chmod +x cURL.sh
$ ./cURL.sh
```

## Output

```
./build/curl/<CURL_VERSION>/curl.xcframework
```

## Configure options

```bash
./configure --host=<HOST> --prefix <PREFIX> \
    --disable-shared \
    --enable-static \
    --with-secure-transport \
    --without-libpsl \
    --without-libidn2 \
    --without-nghttp2 \
    --enable-ipv6 \
    --disable-verbose \
    --disable-dependency-tracking \
    --disable-ldap \
    --disable-ldaps \
    --without-libidn2
```

