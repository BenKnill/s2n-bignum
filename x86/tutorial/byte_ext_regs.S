  .intel_syntax noprefix
  .text

  cmp r15b, 5
  movzx eax, r15b
  movzx edx, r9w
  mov r8b, dl
  ret
