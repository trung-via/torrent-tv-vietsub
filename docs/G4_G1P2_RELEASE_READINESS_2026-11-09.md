# G4 — Current G1+P2 Release readiness (Torrent TV Vietsub)

**Ngày:** 2026-11-09 · **Trạng thái:** `SOURCE_READINESS_PASS / RELEASE_BINARY_NOT_BUILT`.

## Kết luận đã kiểm chứng

G1/G3 của Thor Vietsub v0.3.5 đã được Human thử trên **APK G1+P2 Debug** hiện cài ở Redmi A Pro 55 CN: mở lại trình phát hiện Vietsub, tua nhiều đoạn vẫn đồng bộ, thoát ứng dụng/mở lại Resume tự nhận sub không phải chọn lại. Đây là nghiệm thu **Debug** và **từng tình huống**, không phải kết quả Release.

[HostOps G4 source readiness #42642118985](https://github.com/trung-via/torrent-tv-vietsub/actions/runs/42642118985) — dedicated runner `torrent-tv-vietsub-win`, job `g4readiness`, pinned source commit `59c2bf289ecf9be6f490e494d116eaf9586f93fe`:

| Gate | Bằng chứng |
| --- | --- |
| G4-S0 pin OMP | `52ab2df11bc54749ad7ad3d8771e2f0ce1f9550f`, 2160player `6ba6edd39f5d986ddfae29b5425b8ac0b319844e`; `G4_CURRENT_OMP_SUBMODULE_PINS_PASS` |
| G4-S1 ghép nguồn G1+P2 | G1 Production `apply.ps1` + `verify.ps1` PASS, sau đó P2 overlay `apply.mjs` PASS trên OMP clone tạm |
| G4-S2 main/release source | `P1ProductionSubtitles.kt` ở Android `src/main`, có unit test, không trùng trong `src/debug`/`src/release`; không phát hiện fixture G0/G1c cụ thể tại các source set đã kiểm tra |
| G4-S3 signing guard | Upstream `build.gradle` blob `d0c7a13bf8ad5108e4b82d5bbac8ffd7d522b429` còn logic buộc ký Release; **không bypass** |
| G4-S4 kết quả lệnh | `G4_CURRENT_SOURCE_READINESS=PASS_NOT_BINARY_OR_RELEASE_PASS`, HostOps job SUCCESS; clone cô lập được yêu cầu cleanup |

Những gate trên **không chứng minh DEX/asset manifest của APK Release**, không chứng minh Gradle `assembleRelease` chạy được và không thay cho chữ ký/TV.

## Không áp dụng PR #36

[PR #36](https://github.com/trung-via/torrent-tv-vietsub/pull/36) là hướng kiểm định **unsigned** của G1c/PR29 cũ, có ngoại lệ loại bỏ signing guard trong clone. Không tái sử dụng kết quả hay ngoại lệ đó cho G1 Production + P2 hiện tại; không merge PR36 để làm G4 hiện hành.

## Bước tiếp theo — G4 Release binary (chưa thực hiện)

1. **G4-B1:** xây workflow dedicated Windows **manual only** từ source commit `main` được Brain duyệt, clone OMP/submodule đúng pin, áp G1 Production rồi P2 theo thứ tự. Giữ nguyên signing guard Gradle. Yêu cầu Human duyệt phạm vi sử dụng chữ ký trước khi thực sự ký/publish.
2. **G4-B2:** thực thi `assembleRelease`/unit test trong workspace riêng khi có signing config hợp lệ. Nếu thiếu signing material hoặc config, báo `BLOCKED_SIGNING`; không dùng key Debug, không tự tạo key và không xóa guard chỉ để đạt PASS.
3. **G4-B3:** audit APK sau build: `debuggable=false`, package/applicationId đúng biến thể, ARM32 ABI tương thích, có `P1ProductionSubtitles` compiled ở Release, không chứa G0/G1c fixture/hook, `apksigner verify` PASS, ghi SHA-256 + commit provenance. Không publish public APK/signing secret.
4. **G4-T1:** chỉ sau quyền Human riêng cho *cài/đổi APK* mới kiểm thử trên Redmi, gồm picker SRT/VTT, giữ ON/OFF/OTHER, A→B→A, seek, resume và rollback. Cần kiểm tra `com.spacesarmat.omp.test` Debug hiện cài so với release applicationId `com.spacesarmat.omp`; không mặc định dữ liệu giữa hai package được kế thừa.

## Giới hạn và quyền

- Giữ nguyên Windows TorrServer, TV, APK Debug, dữ liệu người dùng, runner service, firewall. Không cần AIOS.
- Repository hiện **PUBLIC** theo GitHub; source và file Thor đã được Human cho phép công khai. Không đưa secrets, keystore, dữ liệu cá nhân hoặc private artifacts lên repo.
- Source G4 readiness script được commit để kiểm tra lặp lại. Đây là **kiểm tra nguồn**, không có Gradle build, upload, ký APK, ADB, TV control.
- Mục G4 Release cuối cùng vẫn `UNVERIFIED` cho tới khi có ký, audit binary và bằng chứng real TV đúng APK.
