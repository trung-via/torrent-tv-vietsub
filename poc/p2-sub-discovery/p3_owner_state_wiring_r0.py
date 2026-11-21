"""R0 handler overlay; keep the previously staged V2 wiring SHA immutable."""
from __future__ import annotations

from dataclasses import replace

from p3_owner_state_wiring import compose_owner_redmi_status as _compose_v2
from p3_p4_shared_https_route_r0 import make_p3_p4_handler_r0


def compose_owner_redmi_status(**kwargs):
    inspector = kwargs.pop("selected_file_inspector", None)
    wiring = _compose_v2(**kwargs)
    if inspector is not None:
        wiring.current.bind_selected_file_inspector(inspector)
    handler = make_p3_p4_handler_r0(
        wiring.p4_gateway, wiring.signal, wiring.cache, wiring.ingress)
    return replace(wiring, handler=handler)
