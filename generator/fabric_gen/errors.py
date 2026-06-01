"""Error types for fabric_gen. `category` mirrors loom's gen-sv error contract."""


class FabricGenError(Exception):
    category = "error"


class ParseError(FabricGenError):
    category = "parse"


class ShareGroupError(FabricGenError):
    category = "share-group"


class TemplateNotImplemented(FabricGenError):
    category = "unsupported-op"


class RegistryError(FabricGenError):
    category = "registry"
