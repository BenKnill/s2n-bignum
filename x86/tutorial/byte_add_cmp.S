  .intel_syntax noprefix
  .text

  xor eax, eax
  add byte ptr [rdi], sil
  add al, byte ptr [rdi]
  cmp byte ptr [rdi], sil
  ret
