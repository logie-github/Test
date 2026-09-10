Pokopia TCG duel music
======================

Music_TCGDuelTheme1 is packaged as a native Gen1Recomp ChipAsm song in:
  assets/tcg/audio/dueltheme1.lua

Unlike the earlier hand-authored approximation, v1.0.340 is generated from the
actual Pokemon Trading Card Game source score:
  assets/tcg/audio/source/dueltheme1.asm
  pret/poketcg src/audio/music/dueltheme1.asm
  commit 7a75fe810e91dda43538b249c70ee5da14e38686

The TCG audio engine times each note/rest as `speed * length` VBlanks. The
converter maps that to Gen1Recomp ChipSynth with tempo=256, which is exactly
one 60 Hz frame per speed unit. All four channels therefore retain the source
loop length of 7,840 frames (130.6666667 seconds) and restart together.

Finite source loops and music_call subroutines are expanded by:
  assets/tcg/audio/source/build_dueltheme1.py

The source score, converter, generated ChipAsm module, wave pattern, and noise
rhythm all ship in this ZIP. No external music file or network access is
required at runtime.
