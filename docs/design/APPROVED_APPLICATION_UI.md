# Approved application visual language

20 October 2026. The owner approved the Production Recording V3 Phase4A prototype and, in the Phase4B authorization, its application visual language as the future standard for gradual adoption. This records that decision; it does not approve the entire proposed Design System, marketing site, 3D direction or final implementation acceptance. `FACTORY_LEAN_DESIGN_SYSTEM.md` remains untouched.

The authoritative reference is `C:\Users\Temp\Documents\FactoryLean-Production-Recording-V3-Phase4A-Preview`. `src/styles/design-tokens.css` copies its first root token block exactly:256 variables, including primary #2558C8, white surfaces, text #17263A, semantic foreground/background pairs, spacing, type, radii, shadows and motion. No substitute palette or parallel component library was introduced. Font assets and their licenses are copied unchanged from that preview into `public/fonts`.

Use Inter for Latin and IBM Plex Sans Arabic for Arabic. Preserve the reference's16px body,14px labels,22px dialog heading,44px minimum buttons,48px inputs,12px controls/cards and16px modal radius. Arabic labels/buttons use16px and appropriate line height. Desktop task dialog width640px; below640px use the full viewport, a scrollable body and reserved footer. Keep essential units, warnings and permissions visible. Use logical spacing, isolated numeric text, visible focus and reduced-motion overrides.

Reuse existing `Dialog`, translation dictionaries, permission utilities and operational contracts. Apply classes to the touched surface; do not restyle unrelated pages because a token file is imported. Existing Factory Floor controls and shell retain their established presentation in Phase4B. Legacy History uses a wider existing destination; unusual precision may stack receipt values to preserve readability without rounding.

Simple by Default, Detailed on Demand remains mandatory. Ordinary recording shows work, shift, Good, Scrap and Save. Required technician/source/declaration inputs cannot be concealed as optional. Additional WIP output and notes can be disclosed; independent-machine/WIP-processing/startup/manual-shift compatibility stays reachable through the existing recording workflow. Overproduction confirmation appears when the protected backend requests it. Unknown outcomes remain visible until safely resolved.

Localization state must drive displayed text as well as `lang`/`dir`. Store message keys, not already translated messages, for mutable UI state. Include an accessible language action inside a native modal, since the surrounding shell is inert while it is open.

Adoption elsewhere requires its own scoped task and user acceptance. Phase4B does not start a global redesign, correction queue or homepage implementation. Detailed evidence and deviations: [Phase4B report](../production-recording-v3-phase4b.md).
