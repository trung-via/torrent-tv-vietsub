# P3-LOCAL_EN_DIRECT — Ưu tiên phụ đề EN có sẵn trước OpenSubtitles

**HUMAN APPROVED — 2026-11-14 · SOURCE-ONLY DRAFT**, chưa chạy trên phim thật.  
Issue [#144](https://github.com/trung-via/torrent-tv-vietsub/issues/144). PR phụ thuộc: [#140](https://github.com/trung-via/torrent-tv-vietsub/pull/140) automatic source/LEAN120; [#143](https://github.com/trung-via/torrent-tv-vietsub/pull/143) owner-session Windows agent; [#142](https://github.com/trung-via/torrent-tv-vietsub/pull/142) P3-TRIGGER; [#131](https://github.com/trung-via/torrent-tv-vietsub/pull/131) D3 and [#120](https://github.com/trung-via/torrent-tv-vietsub/pull/120) P4. **Không** giả định những Draft này đã merged hay đang chạy.

## Yêu cầu sản phẩm

Khi TV OMP đã nhận lệnh phát một **file phim/tập chính xác**, chế độ Vietsub AI đã được owner bật một lần và viewer subtitle=ON:

1. VI sẵn có phù hợp → **dùng ngay**, không OpenSubtitles, không Gemini. P3-TRIGGER kiểm tra VI trước khi gọi đường EN.
2. EN sidecar **đúng stem tên video** `<video-stem>.en.srt` / `.eng.srt` / `.english.srt` (hoặc `.vtt`) trong vùng phim cục bộ của owner → validate → cache D2 private → **existing #140.after_en_cached** → existing P2/Gemini 4 Hydrogen High LEAN120; **0 OpenSubtitles GET/POST**.
3. Không có sidecar nhưng **video MKV/MP4/WebM đầy đủ ở laptop** → dùng owner-installed `ffprobe` dò các track ngôn ngữ EN, ưu tiên text codecs `subrip/ass/ssa/webvtt/mov_text/text`, owner-installed `ffmpeg` trích xuất thành SRT → validate → same P2. Không OCR cho PGS/VobSub.
4. Không có nguồn EN cục bộ **đọc được** (chỉ thấy tên track ở TV, phim chỉ stream từ TorrServer, file chưa hoàn chỉnh, image-only) → chuyển đường cũ [#140] VI_FAST → EN provider → LEAN120. Lỗi xác thực, EN sidecar sai tên, nội dung lỗi, symlink/traversal, nhiều EN text track không rõ lựa chọn: **HOLD**, không bất ngờ gây quota GET/POST/model.

**Quan trọng:** `PlayerEngine.subtitleTracks()` trên TV cho biết track và codec, **không phải bytes của phụ đề**. Có track EN trong danh sách OMP không bảo đảm laptop được phép đọc file: TorrServer có thể stream mà không lưu video đầy đủ ở máy Windows. Không dùng stream URL LAN hoặc trích xuất qua raw TorrServer API trong slice này; cần chứng minh quyền truy cập nguồn video trực tiếp trước.

## Cấu trúc tích hợp

```text
REAL OMP PlayRequest (owner-authenticated TV session, server, hash, fileIndex)
 -> P3-TRIGGER (#142): only actual play/next, auto ON & viewer ON
 -> inspect verified VI track: present -> reuse VI
 -> local media resolver: *trusted* current TorrServer selected-file binding
 -> LocalMediaSelection (exact private absolute movie path / exact EN sidecar)
 -> local_en_direct.find_local_english() [no network/provider, bounded]
    ├ exact EN SRT -> read (<=256 KiB) -> QA
    ├ exact EN VTT -> local ffmpeg -> SRT -> QA
    ├ text English MKV track -> local ffprobe + ffmpeg -> SRT -> QA
    ├ no LOCAL EN available -> existing #140 VI_FAST/OpenSubtitles fallback
    └ untrusted/wrong/ambiguous/corrupt -> STOP (no quota)
 -> existing D2 write_private_cache(Media(server,hash,index,name), Asset(EN))
 -> existing #140 after_en_cached(Asset,path)
 -> existing P2 LEAN120 120 cues / <=6500 chars per window
 -> D3 exact authenticated TV binding -> P4 signed updates, separately
```

**Programmatic seam** (owner-process integration after real event verification):

```python
# Supplied by a *trusted* same-session OMP/TorrServer resolver, not external JSON.
# video_name must exactly match LocalMediaSelection.video_name.
result = flow.selected_media(
    video_name,
    local_source=LocalMediaSelection(
        attested=True, active=True, owner_authorized=True,
        viewer_choice="ON", local_vi_state="ABSENT",
        server_id=opaque_owner_server, torrent_hash=trusted_infohash,
        file_index=trusted_file_index, video_name=video_name,
        private_media_root=owner_allowed_absolute_root,
        en_sidecar_path=owner_matched_en_sidecar, # or None
        video_path=verified_complete_local_video, # or None
        video_file_complete=video_is_fully_local, # for embedded only
    ),
)
```

**Các boolean `attested/active/owner_authorized` chưa thực hiện xác thực.** Chúng là precondition cho source-only adapter; chỉ event/resolver được phép của owner Windows và TV kiểm chứng mới được set. D3/P4 còn phải tự verify media/session key; file name/hash cục bộ hoặc SHA của SRT không phải HMAC chứng minh source đến đúng TV.

## Ranh giới an toàn

- Chỉ owner-local private absolute path dưới thư mục media được owner cho phép; không scan thư mục, không đoán file/sub theo tên tiêu đề, không tự download film, không đọc symlink, không chia sẻ tên file/địa chỉ IP/media bytes lên repo PUBLIC.
- FFmpeg/ffprobe **không tự cài** và chỉ được gọi từ tiến trình local owner sau khi xác minh bộ công cụ; chạy `-protocol_whitelist file,pipe`, args array không shell, timeout 20/45 giây, cap probe JSON và cap SRT 256 KiB. File phim phải đã **đầy đủ cục bộ**; không phát HTTP, không thêm WAN/UPnP/firewall.
- `selected_media(...local_source=...)` trước khi gọi OpenSubtitles. Người dùng đã bật auto + cloud upload một lần ở owner process theo #140; chưa có key/hết quyền dùng Gemini thì fail closed, không hỏi lại theo từng phim.
- `find_local_english` xác nhận nguồn có nhãn ngôn ngữ EN và timeline hợp lệ; **không thể tự chứng minh độ chính xác ngữ nghĩa tiếng Anh hoặc khớp hình ảnh** chỉ từ metadata. PGS/VobSub image không OCR trong scope.
- Cache dùng `write_private_cache` của D2, định danh `server+infohash+fileIndex`, tránh nhầm cùng tên file từ hai torrent; P2 worker giữ checkpoint/uncertain-claim, không cần daemon/translator thứ hai.
- `LocalMediaSelection` nếu không được truyền từ event thật, code cũ của #140 vẫn chạy như trước; **nhánh này không tự cài owner agent #143 hoặc ghép OMP TV thật**.

## Bằng chứng/gates

| Gate | Yêu cầu | Trạng thái |
| --- | --- | --- |
| LOCAL_SOURCE_OFFLINE | SRT/VTT/ffprobe fake + lỗi track + private path + flow #140 0 GET/POST | Chờ CI exact HEAD |
| LOCAL_OWNER_FILES | owner Windows thật có EN sidecar hoặc MKV đầy đủ; FFmpeg đã được xác minh | NOT_RUN |
| LOCAL_REAL_TO_P2 | exact selected torrent/file EN thật → configured LEAN120 API thực tế | NOT_RUN |
| REAL_EVENT_BIND | OMP→owner Windows event/session chính xác, viewer ON & VI absent | NOT_RUN |
| REAL_P4_REDMi | authenticated subtitle revision no-picker đúng TV; cue 131 | NOT_RUN |

Đánh giá riêng từng gate: CI synthetic không đại diện FFmpeg trên file thật, kết nối OMP, cloud quota hay hiển thị phụ đề trên Redmi.
