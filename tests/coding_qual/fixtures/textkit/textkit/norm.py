def require_text(name, value):
    """Raise TypeError naming the parameter when value is not a str; return value."""
    if not isinstance(value, str):
        raise TypeError(f"{name} must be a str, got {type(value).__name__}")
    return value
