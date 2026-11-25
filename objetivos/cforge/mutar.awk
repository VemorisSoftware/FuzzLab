BEGIN { srand(semilla) }
{ l[NR] = $0 }
END {
  n = NR; if (n == 0) exit
  tipo = int(rand() * 8)
  k = int(rand() * n) + 1
  tok[0]="{"; tok[1]="}"; tok[2]="("; tok[3]=")"; tok[4]="["; tok[5]="]"; tok[6]="si"; tok[7]="funcion"; tok[8]="retornar"; tok[9]="\""; tok[10]=","; tok[11]="="; tok[12]="."; tok[13]="mientras"; tok[14]="clase"; tok[15]="sea"; tok[16]="99999999999999999999999999"; tok[17]="-"; tok[18]="?"; tok[19]="=>"; tok[20]="coincidir"; tok[21]="comptime"; tok[22]="async"; tok[23]="aguardar"; tok[24]="..."; tok[25]="\\"; tok[26]="${"; tok[27]="//"; tok[28]="/*"; tok[29]="esto"
  for (i = 1; i <= n; i++) {
    s = l[i]
    if (i == k) {
      if (tipo == 0) continue                                   # borrar línea
      if (tipo == 1) { print s; print s; continue }              # duplicar
      p = int(rand() * (length(s) + 1))
      if (tipo == 2) s = substr(s, 1, p) tok[int(rand()*30)] substr(s, p + 1)   # insertar
      if (tipo == 3) s = substr(s, 1, p) substr(s, p + 1 + int(rand()*6))        # borrar caracteres
      if (tipo == 4) { j = int(rand()*n)+1; s = l[j] }                            # copiar otra línea
      if (tipo == 5) { for (r = 0; r < 40; r++) s = "(" s ")" }                  # anidar
      if (tipo == 6) s = s " " tok[int(rand()*30)] " " tok[int(rand()*30)]
      if (tipo == 7) { gsub(/[0-9]+/, "9223372036854775808", s) }
    }
    print s
  }
}
