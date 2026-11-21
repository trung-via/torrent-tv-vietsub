"""R2 P3→Owner→existing P2→existing P4 rolling composition.

V2 signed state/route/policy and F6 worker source pins remain byte-for-byte
unchanged. This is one opt-in Owner entrypoint, one paired HTTPS listener,
and one existing owner event/translator.
"""
from __future__ import annotations

from dataclasses import dataclass

from automatic_lean120_worker import AutomaticLean120Worker
from paired_activation import PairedActivation
from owner_r2_progressive_registry import R2OwnerProgressiveRegistry
from owner_r2_progressive_worker import R2ProgressiveWorker
from owner_r2_verified_processor import R2VerifiedV3Processor
from p3_owner_state_wiring import OwnerP3StatusComposition
from p3_owner_state_wiring_r0 import compose_owner_redmi_status as _compose_r0
from p3_p4_shared_https_route_r0 import make_p3_p4_handler_r0


@dataclass(frozen=True)
class R2OwnerP3StatusComposition(OwnerP3StatusComposition):
    def trusted_v3_factory(self, existing_flow: object):
        registry = self.ready_registry
        worker = getattr(existing_flow, "worker", None)
        if (not isinstance(registry, R2OwnerProgressiveRegistry)
                or not isinstance(worker, AutomaticLean120Worker)):
            return super().trusted_v3_factory(existing_flow)
        if not isinstance(worker, R2ProgressiveWorker):
            existing_flow.worker = R2ProgressiveWorker(
                existing=worker, emit=getattr(existing_flow, "emit", print))
        # P4 HTTPS runs concurrently with P2: it may rehydrate the latest
        # committed checkpoint even after a lost delivery callback/restart.
        # This binding is read-only and never starts another model operation.
        registry.bind_existing_flow(existing_flow)
        return R2VerifiedV3Processor(
            progressive_registry=registry,
            flow=existing_flow,
            private_media_root=self.private_media_root,
            read_verified_current_playback=self.current.read_v3,
            read_verified_torrserver_file=self.current._ts,
            locate_owner_pinned_files=self.locate_owner_pinned_files,
            on_vietsub_ready=registry.register)


def compose_owner_redmi_status(**kwargs) -> R2OwnerP3StatusComposition:
    secret = kwargs.get("paired_device_secret")
    if kwargs.get("enable_verified_vietsub_ready") is not True:
        raise ValueError("OWNER_R2_VERIFIED_READY_REQUIRED")
    wiring = _compose_r0(**kwargs)
    registry = R2OwnerProgressiveRegistry(
        read_verified_current_playback=wiring.current.read_v3)
    gateway = PairedActivation(
        device_secret=secret, supplied={},
        authenticated_vietsub_factory=registry.resolve,
        authenticated_progressive_factory=registry.resolve_progressive)
    handler = make_p3_p4_handler_r0(
        gateway, wiring.signal, wiring.cache, wiring.ingress)
    fields = vars(wiring).copy()
    fields.update(handler=handler, p4_gateway=gateway, ready_registry=registry)
    return R2OwnerP3StatusComposition(**fields)
