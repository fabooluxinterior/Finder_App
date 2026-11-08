Codec WebAssembly binaries from jSquash (Apache-2.0, Google Squoosh codecs:
mozjpeg, libpng/oxipng, libwebp, squoosh resize). Vendored so they ship with
the edge function bundle (see `static_files` in supabase/config.toml).

| file | package |
|---|---|
| mozjpeg_dec.wasm | @jsquash/jpeg@1.6.0 |
| squoosh_png_bg.wasm | @jsquash/png@3.1.1 |
| webp_enc_simd.wasm | @jsquash/webp@1.5.0 |
| webp_dec.wasm | @jsquash/webp@1.5.0 |
| squoosh_resize_bg.wasm | @jsquash/resize@2.1.1 |

Update all of them together with the version pins in `_shared/image.ts`.
