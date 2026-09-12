"""Tokenizer, byte for byte the same rule main.lua's `tokenize` uses."""
import re

def is_word_byte(c):
    o = ord(c)
    return (48 <= o <= 57) or (97 <= o <= 122) or o == 35 or o >= 128

def tokenize(text):
    text = (text or "").lower()
    out, i, n = [], 0, len(text)
    while i < n:
        c = text[i]
        o = ord(c)
        if o in (32, 9, 10, 13):
            i += 1
        elif o == 60:  # '<'
            j = text.find(">", i + 1)
            if j >= 0:
                out.append(text[i:j + 1]); i = j + 1
            else:
                out.append(c); i += 1
        elif is_word_byte(c):
            j = i
            while j < n and is_word_byte(text[j]):
                j += 1
            if j < n and text[j] in ("'", "-") and j + 1 < n and is_word_byte(text[j + 1]):
                j += 1
                while j < n and is_word_byte(text[j]):
                    j += 1
            out.append(text[i:j]); i = j
        else:
            out.append(c); i += 1
    return out

PUNCT = {".", ",", "?", "!", ":", ";", "%", ")", "]"}
OPEN = {"(", "["}

def detokenize(tokens):
    s = ""
    for t in tokens:
        if t in PUNCT:
            s = s.rstrip() + t + " "
        elif t in OPEN:
            s += t
        else:
            s += t + " "
    return s.rstrip()

def escape(t):
    return t.replace("\\", "\\\\").replace("\t", "\\t").replace("\n", "\\n").replace("\r", "\\r")
