try:
    import debugpy
    import os
    import json
    debug_port = os.getenv("DEBUG_PORT", None)
    if debug_port:
        debug_port_int = int(debug_port)
        debugpy.listen(("0.0.0.0", debug_port_int))
except:
    pass