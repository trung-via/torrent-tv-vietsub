# Kiểm tra phụ đề EN trực tiếp từ torrent/MKV — Owner Windows

Áp dụng cho **phim/torrent mà chủ sở hữu được phép sử dụng**, trên **chính PC
chạy TorrServer**. Không nhập infohash, link torrent riêng tư, cookie, mật khẩu
hay phụ đề có bản quyền vào Issue/PR công khai.

## Phân biệt ba nguồn

1. **EN nhúng trong MKV:** track `subtitle` bên trong chính tệp video.
   TorrServer `/ffp` liệt kê stream; `ffmpeg` đọc `/play` và xuất ra SRT.
2. **EN rời trong torrent:** tệp `.en.srt/.ass/.vtt` nằm cạnh MKV. TorrServer
   `/subs` đọc được ngay, không gọi OpenSubtitles và không cần `ffmpeg`.
3. **EN từ website:** tải thủ công bằng trình duyệt ở trang cung cấp hợp pháp
   (ví dụ `https://www.opensubtitles.com/`). Không dùng crawler, URL download
   nội bộ, cookie phiên hay cách né quota API để tự động tải.

**Magnet URL / tệp `.torrent` chỉ là metadata và địa chỉ tìm peer:** nó không
chứa nội dung phụ đề MKV. Cần có peer/các mảnh torrent được cache hoặc tệp MKV
đã tải trước đó. Xuất toàn bộ phụ đề nhúng có thể phải đọc đáng kể dữ liệu video
vì các cue nằm rải theo thời gian; việc có track EN không bảo đảm trích xuất nhanh.

## A. Thử trực tiếp TorrServer bằng PowerShell

Mở PowerShell trên PC Windows đang chạy TorrServer. Thay **port** đúng của
TorrServer, dùng `localhost` (không đưa TorrServer ra Internet):

```powershell
$ts = 'http://127.0.0.1:8090'  # 8090 chỉ là ví dụ
$hash = Read-Host 'Torrent infohash (40 hoặc 64 ký tự hex)'
$idx = [int](Read-Host 'File id/index trong torrent')
$metadata = Invoke-RestMethod -Method Post -Uri "$ts/torrents" -ContentType 'application/json' -Body (@{action='get'; hash=$hash} | ConvertTo-Json -Compress)
$metadata.file_stats | Select-Object id,path,length
```

Chỉ tiếp tục khi `id` trùng **đúng file MKV đang phát**. Nếu `file_stats`
trống, kiểm tra danh sách tệp trực tiếp trong giao diện TorrServer; các bản
TorrServer cũ có thể lưu danh sách trong `data.TorrServer.Files`.

Xem track nhúng (không tải phụ đề, không gọi API phụ đề):

```powershell
$probe = Invoke-RestMethod -Uri "$ts/ffp/$hash/$idx"
$probe.streams | Where-Object { $_.codec_type -eq 'subtitle' } |
    Select-Object index,codec_name,@{Name='language';Expression={$_.tags.language}},disposition
```

Chỉ chọn dòng có `language = eng/en` và codec **text** như `subrip`, `ass`,
`ssa`, `webvtt`, `mov_text`. `hdmv_pgs_subtitle`/`dvd_subtitle` là bitmap,
không xuất SRT text bằng lệnh dưới đây (cần OCR riêng).

Cài FFmpeg từ trang chính thức nếu máy chưa có, sau đó xác nhận
`ffmpeg -version`. Thay số `3` sau `0:` bằng **index chính xác do `/ffp`
trả về** (không phải thứ tự 0/1 của riêng danh sách phụ đề):

```powershell
$folder = Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\ENManualTest'
New-Item -ItemType Directory -Path $folder -Force | Out-Null
$output = Join-Path $folder 'source.en.srt'
ffmpeg -nostdin -hide_banner -loglevel error -i "$ts/play/$hash/$idx" -map 0:3 -vn -an -dn -c:s srt -f srt "$output"
if ($LASTEXITCODE -eq 0) { Get-Content $output -Encoding utf8 -TotalCount 8 }
```

Thử **EN sidecar** nếu `/ffp` không có EN text:

```powershell
Invoke-RestMethod -Uri "$ts/subs/$hash/$idx" |
    Select-Object index,name,lang,format
```

Nếu có EN với `index=4`, tải **WebVTT** bằng endpoint công khai của chính
TorrServer (thay đúng index):

```powershell
Invoke-WebRequest -Uri "$ts/subs/$hash/$idx`?track=4&format=vtt&encoding=utf8" -OutFile (Join-Path $folder 'source.en.vtt')
```

Trình duyệt trên **cùng PC** cũng có thể mở `http://127.0.0.1:8090/`,
`/ffp/<infohash>/<file-id>` và `/subs/<infohash>/<file-id>` để xem JSON.
Nhớ đăng nhập TorrServer theo cấu hình riêng nếu nó bật xác thực; không
đưa mật khẩu vào URL/log. Windows PowerShell 5.1 có thể trả `-OutFile` khác
PowerShell 7; nếu bật xác thực, sử dụng phiên/công cụ đã cấu hình an toàn.

## B. MKV có sẵn trên ổ đĩa

Khi người dùng đã **tải xong** tệp MKV hợp pháp, có thể bỏ TorrServer:

```powershell
ffprobe -v error -show_entries stream=index,codec_type,codec_name:stream_tags=language,title -of json 'D:\Media\film.mkv'
ffmpeg -nostdin -i 'D:\Media\film.mkv' -map 0:3 -vn -an -dn -c:s srt 'D:\Media\source.en.srt'
```

Hoặc dùng MKVToolNix: `mkvmerge -J 'D:\Media\film.mkv'` để xem **track ID
riêng của MKVToolNix**, sau đó `mkvextract 'D:\Media\film.mkv' tracks
3:'D:\Media\source.en.srt'`. Track ID của `mkvextract` **không bắt buộc
trùng** `stream.index` của FFmpeg. Track ASS có thể xuất `.ass`, track PGS
xuất `.sup`: đừng đặt nhãn `.srt` rồi coi là text.

## C. Thử thủ công trên website phụ đề

1. Trên trình duyệt, mở `https://www.opensubtitles.com/`, tìm đúng tên
   phim, năm phát hành, mùa/tập (nếu có) và chọn ngôn ngữ **English**.
2. So khớp `WEB-DL/BluRay`, nhóm release, thời lượng/FPS; tải tệp qua nút
   download **được website cung cấp cho tài khoản của chính Ngài**.
3. Giải nén `.zip` nếu có, mở `.srt`/`.vtt` và thử sync trong trình phát.
   Chỉ nhập vào luồng dịch sau khi xác nhận nội dung/timestamp phù hợp.

Đường website chỉ là **thao tác thủ công**. Nó không khắc phục được quota
REST `POST /download` bằng cách lén lấy URL nội bộ hoặc tự động scraping.

## D. Cách đọc kết quả của Owner mới

| Mã | Ý nghĩa |
| --- | --- |
| `AUTO_EN_SOURCE=LOCAL_DIRECT` | Có EN trực tiếp đã được kiểm tra từ Owner |
| `AUTO_EN_SOURCE=TORRENT_EMBEDDED` | Đã xuất SRT EN từ track MKV |
| `AUTO_EN_SOURCE=TORRENT_SIDECAR` | Đã đọc EN rời trong chính torrent |
| `AUTO_EN_EMBEDDED=EMBEDDED_EN_TEXT_TRACK_NOT_FOUND` | Không có EN text có nhãn `eng/en`; không tự đoán `und` |
| `AUTO_EN_EMBEDDED=EMBEDDED_EN_EXTRACT_UNAVAILABLE` | FFmpeg không có, stream/peer lỗi, quá hạn hoặc demux thất bại |
| `AUTO_EN_SOURCE=UNAVAILABLE_NO_PROVIDER_FALLBACK` | Chưa có EN để dịch; **không gọi OpenSubtitles** |

Hạn chót extraction tự động hiện là **45 giây** cho một lần thử; không có
API GET/POST OpenSubtitles, không có lệnh tải phim nguyên tệp tự động.
Không thể cam kết P4/TV PASS khi chưa chạy một thử nghiệm thật trên Owner.

Nguồn kỹ thuật: [TorrServer upstream README](https://github.com/YouROK/TorrServer#readme),
[TorrServer Swagger](https://github.com/YouROK/TorrServer/blob/master/server/docs/swagger.json),
[FFmpeg](https://ffmpeg.org/ffmpeg.html),
[ffprobe](https://ffmpeg.org/ffprobe.html),
[MKVToolNix](https://mkvtoolnix.download/doc/mkvextract.html).
