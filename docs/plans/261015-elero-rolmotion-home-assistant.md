# Elero RolMotion-868: favourites and silent movement in Home Assistant

Date: 2026-10-15
Status: planned; discovery and implementation pending.

## Goal

Add four controls for each RolMotion-868 shutter in Home Assistant:

- Favourite 1: recall the stored intermediate position.
- Favourite 2: recall the stored ventilation position.
- Silent open: open fully using the quiet travel profile.
- Silent close: close fully using the quiet travel profile.

Reuse the existing Fibaro Home Center 3 and its local API. The preferred first implementation is
one reusable Home Assistant REST command plus scripts and dashboard buttons. Build a custom
integration only if the simpler approach proves insufficient.

## Known installation

- Motors: elero RolMotion-868.
- Controller: master HC3-00031056.
- Firmware reported by the user: 5.220.15, with the controller reporting up to date.
- HC3 is already connected to Home Assistant through the Fibaro integration.
- Shutters already appear in Home Assistant with open, stop and close controls.
- The dashboard includes Living room S/L, Balcony entrance, Balcony L, Office L/S,
  Kids room and Bedroom. Confirm the actual entity and HC3 device IDs during discovery.

## Findings and remaining uncertainty

Home Assistant's Fibaro integration supports HC3 over a local connection and can execute HC3
scenes. Its inspected cover implementation does not expose dedicated elero favourite-recall or
silent-movement actions. Changing the cover card alone will not expose those functions.

RolMotion radio motors support standard and quiet travel profiles, as well as stored intermediate
and ventilation positions. Their availability at motor level does not prove that every function
is exposed by the installed HC3 device API.

Fibaro's API uses the device-action pattern:

```text
POST /api/devices/{device_id}/action/{action_name}
Content-Type: application/json

{"args": []}
```

The exact action names and argument values for the two favourites and silent movement are
**not yet verified on this controller**. Do not invent names or assume that a command named
like a favourite setter recalls a position rather than reprogramming it. A numeric action
argument count alone does not establish argument meaning.

## Phase 1: Read-only discovery

1. Locate the HC3 local address and the existing Home Assistant configuration/deployment method.
   Use the repository's infrastructure references and the installed integration configuration.
2. Obtain one representative shutter's HC3 device ID, distinct from its Home Assistant entity ID.
3. Read the device metadata while authenticated locally:

   ```text
   GET http://HC3_IP/api/devices/SHUTTER_ID
   ```

   If necessary, find its ID by reading `GET /api/devices` and matching its name.
4. Inspect `id`, `name`, `type`, `baseType`, `interfaces`, `actions`, and relevant properties.
5. Inspect the controller's API documentation for action schemas. If metadata does not establish
   semantics, inspect the HC3 web interface's network requests when the user invokes an existing
   favourite or silent movement control. Those clicks move the shutter; use a suitable shutter
   and coordinate timing with the user.
6. Record the verified action name and JSON arguments for each of the four functions, plus the
   mapping between HC3 IDs and Home Assistant entities for all shutters.

Do not save credentials or full configuration dumps in this repository. Follow repository policy
for operator credentials: Windows Credential Manager. Any HA runtime credentials must be
provisioned separately through HA's existing secret mechanism, outside this repository.

## Phase 2: Implement the simplest API bridge

Home Assistant configuration belongs in the actual service configuration location, not in this
infrastructure index repository. Locate that source before making deployment changes.

The following is a proposed configuration shape, not a tested installation-ready configuration.
Replace `HC3_IP`, confirm the controller's authentication/scheme, and merge with an existing
`rest_command` section if present:

```yaml
rest_command:
  hc3_shutter_action:
    url: "http://HC3_IP/api/devices/{{ device_id }}/action/{{ command }}"
    method: POST
    authentication: basic
    username: !secret hc3_username
    password: !secret hc3_password
    headers:
      X-Fibaro-Version: "2"
    content_type: "application/json"
    payload: '{{ {"args": arguments | default([])} | to_json }}'
```

1. Confirm the endpoint, authentication and request body against the installed HC3 API.
2. Configure the reusable REST command and runtime secrets in the appropriate HA location.
3. Create scripts for the four verified operations, supplying the HC3 device ID, verified
   command name and correctly typed argument list. Use a fixed operation mapping in the scripts.
4. Expose scripts as dashboard buttons alongside the existing shutter controls.
5. Retain the existing Fibaro integration for basic movement and any available state reporting.

Do not substitute HA percentage positioning for the motor's two stored favourites. Do not use
delays or repeated open/close calls to imitate a remote long press without verifying protocol
behaviour. Calling the API successfully does not establish that movement used the quiet profile.

## Phase 3: Validate on one shutter, then extend

- Validate the HA configuration and load it using the supported mechanism for this installation.
- Test normal stop remains available before trying the extra controls.
- Recall each favourite and verify the shutter reaches the previously stored position.
- Confirm favourite positions were not overwritten.
- Test silent open and silent close over a meaningful travel distance; verify reduced speed
  and sound compared with normal operation, rather than relying only on the HTTP response.
- Check error reporting for unsuccessful API calls and HA script traces.
- Verify state feedback after movement, including any existing `Unknown` states. Do not claim
  exact percentage feedback unless the controller actually provides it.
- Extend the verified mapping to the remaining shutters and test each device ID independently.
- Keep movement tests sequential so a wrong ID or command is immediately apparent.

## Fallback

If the HC3 does not expose the extra functions as direct device actions, configure manually
triggered HC3 scenes for the required operations and invoke them through HA's existing Fibaro
scene support. Verify which functions are available in this firmware's scene editor first.

A custom HA integration is a later option for automatic discovery and dedicated button entities;
it still requires the same verified HC3 commands and is not the fastest initial implementation.

## Completion criteria

All configured shutters have working Favourite 1, Favourite 2, Silent open and Silent close
buttons in HA; existing movement controls remain functional; credentials remain outside the
repository; verified commands, deployment steps and any feedback limitations are documented.

## References

- [Home Assistant Fibaro integration](https://www.home-assistant.io/integrations/fibaro/)
- [Fibaro cover implementation](https://github.com/home-assistant/core/blob/dev/homeassistant/components/fibaro/cover.py)
- [Home Assistant RESTful Command](https://www.home-assistant.io/integrations/rest_command/)
- [Fibaro REST API documentation](https://manuals.fibaro.com/content/other/FIBARO_System_REST_API.pdf)
- [Fibaro Lua/API action documentation](https://manuals.fibaro.com/content/other/FIBARO_System_Lua_API.pdf)
- [elero RolMotion quiet-mode explanation](https://www.elero.de/de/silentmotion/)

Public documentation and the current HA source are research references. The installed HC3 API
and installed HA version must be checked before implementation.
