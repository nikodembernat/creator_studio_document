## 0.1.0

- Initial release.
- Models for every type of Keynote Interchange Format (`.keyx`), generated
  from upstream creator-studio-doc-format 0.1.0, with its wire codec:
  presets, overrides, tagged unions, version gating, and unknown keys kept on
  a round trip.
- `KeyxDocument` and `Package`, which read and write a `.keyx` archive, from a
  path (eagerly or lazily) or from bytes, with its presets, manifest, and
  resources.
- `navigation.dart`: `iterateModels`.
- `validation.dart`: `validateDocument`, for a check before every save.
- `authoring.dart`: slides from a theme's layouts, with their text and image
  placeholders filled in by name.
- Ports of upstream's example scripts, guide, and agent skill.
