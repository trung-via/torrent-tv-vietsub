# P1a — Bốn finding từ V1-method desk audit

**Human decision:** ngày 2026-10-25, đồng ý hướng PR #10 nhưng yêu cầu giữ F-01, F-02, F-03, F-04 và chỉnh các acceptance/proof gates.
**Audit mode:** tham khảo AIOS Adaptive Brain Audit V1 (CONSTRUCT → ADVERSARIAL_AUDIT_AND_RECONCILE, tám lens); **không phải** authenticated V1 canonical audit / Decision Packet, Runtime RESULT, Reviewer PASS hoặc AIOS TASK admission.
**Source at audit:** torrent-tv-vietsub/main `67b769ce29ce9c166472f97ef46b37170a525e29`; PR10 head trước reconciliation `d6023694d3f53a01395c738bbabd2242af4a0215`; OMP upstream pin `52ab2df11bc54749ad7ad3d8771e2f0ce1f9550f`; submodule `6ba6edd39f5d986ddfae29b5425b8ac0b319844e`. Refresh these bindings before official TASK.

## Stage 1 — Candidate

Outcome: chứng minh VLC render được SRT local không nằm trong torrent mà không làm hỏng D-pad/audio. A (torrent subtitle sẵn có) không chứng minh external; B (fixture debug-only vào app-private, predeclared) là PoC hẹp nhất; C (SMB/phone/backend) thêm bề mặt/trust chưa cần. Value/ROI chưa đo = UNKNOWN.

## Stage 2 — Tám lens

| Lens | Kết quả |
| --- | --- |
| AUTHORITY_BOUNDARY | Human approved P1 direction ≠ AIOS admission, dispatch, REVIEW hoặc merge bỏ review |
| SCOPE_NON_GOALS | G0 render fixture không đồng nghĩa importer G1 hoặc hot-add G2 |
| PROVENANCE_LINEAGE | Upstream SHA và 2160player gitlink xác định; app main chưa nhập OMP; PR9/10 overlap docs |
| FAILURE_MODE_COUNTEREXAMPLES | Invalid URI, sai encoding, reopen re-inject, đổi tập, permission denied |
| AC_CONSISTENCY_COMPLETENESS | G0/G1/G2/G3/G4 khác nghĩa, có trạng thái proof riêng |
| VERIFICATION_OWNERSHIP_ORDERING | build OMP upstream/CI/mock không chứng minh APK fork chạy Redmi |
| PORTABILITY_PRIVACY_BOUNDEDNESS | Không tạo SMB/secret mới; redact stream URL/magnet/token và fixture media |
| SIMPLIFICATION_DUPLICATE_AUTHORITY | Tái sử dụng QueueItem.subtitles và VLC addSlave, không xây mới server/player |

## Findings, risk and disposition

### F-01 — Gộp nhầm proof local fixture thành E2E

**Severity:** MATERIAL. **Disposition:** ADDRESSED_IN_DOCS, implementation/tests pending.
Debug fixture đóng gói trong APK và chép vào filesDir chỉ chứng minh G0 predeclared SRT local, **không** chứng minh file ngoài APK được nhập, hot-add, persistence hoặc user flow. Labels: `LOCAL_SRT_RENDER_PASS` sau G0 Redmi thật; `EXTERNAL_SRT_E2E_PASS` chỉ sau G1 Redmi thật; G2 hot-add riêng.

### F-02 — Fixture không đại diện và persistence giả

**Severity:** MATERIAL. **Disposition:** ADDRESSED_IN_DOCS, tests pending.
Bốn cue SRT tự tạo có timestamp/các dấu tiếng Việt nhưng không khớp lời thoại video bất kỳ. G3 cần clip hợp pháp có cue kiểm soát. Khi mở lại, debug code tự re-attach có thể làm giả bằng chứng ghi nhớ. Tắt injection khi thử persistence G1; đổi media/episode, chỉ kiểm embedded track nếu sample có.

### F-03 — Debug code có thể lọt release

**Severity:** MATERIAL. **Disposition:** ADDRESSED_IN_DOCS, artifact verification pending.
Ưu tiên `android/app/src/debug` cho asset và code probe; test hook mặc định OFF. Nếu production source cần gọi vào helper, phải chứng minh bản release không đóng gói/có thể kích hoạt nhánh PoC. Review release APK source/asset/dex và regression theo build variant; rollback được, không làm thay đổi player production mặc định.

### F-04 — Provenance và quyền thực thi thiếu

**Severity:** MATERIAL. **Disposition:** ADDRESSED_IN_DOCS, EXECUTION_BLOCKED_PENDING_GATES.
Target `main` chỉ có docs, chưa có OMP source. Historical runner smoke `40128964785` và pinned-upstream build+unit tests `40159082083` PASS **không** chứng minh P1 fork/TV test hay AIOS dispatch. Phải có legal/license/source pin, isolated workspace/runner, branch scope và current admission/cross-repo authority nếu dùng AIOS. Real-TV proof cần APK SHA256 và firmware/API/ABI; không tự merge/run/dispatch.

## Reconciliation/closure

Các findings F-01…F-04 có **phương án xử lý trên giấy**, chưa có implementation/proof. Contract, PRD, Roadmap, ADR-0006 và PoC plan ghi rõ gate G0–G4. Tám lens đã được cân nhắc trong desk review; kết luận chỉ là **BOUNDED DESIGN RECONCILIATION**, không phải V1 canonical CANDIDATE, REVIEW PASS hoặc hardware E2E.

Human đồng ý **hướng PR #10**; PR #9 cùng sửa Contract/PRD/Roadmap nên cần reconcile trước merge. Independent review pending. Không tự mở Windows SMB/Firewall, không dùng AIOS runner, không auto source import/build/TV sideload/publish.
