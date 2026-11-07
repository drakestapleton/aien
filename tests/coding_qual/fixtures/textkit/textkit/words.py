from .norm import require_text


def count_words(s):
    """Number of whitespace-separated words in s."""
    require_text("s", s)
    return len(s.split())


def title_case(s):
    """Every word with its first letter upper-cased and the rest lower-cased, single spaces."""
    require_text("s", s)
    return " ".join(w[:1].upper() + w[1:].lower() for w in s.split())


def truncate_words(s, n):
    """The first n words of s joined by single spaces; all of them when s has n words or fewer."""
    require_text("s", s)
    words = s.split()
    return " ".join(words[:n]) if len(words) > n else " ".join(words)
