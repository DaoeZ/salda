# Corpus de regresión del parser

Cada caso = un directorio con `input.txt` (filas del ticket tras la fase de
geometría, una por línea) y `expected.json` (verdad de referencia).

- `mustPass: true` → el caso es un contrato: si deja de pasar, la CI rompe.
- `mustPass: false` → limitación conocida y documentada; cuando una mejora
  lo haga pasar, se promociona a `true`.

**Origen:** los casos iniciales son recreaciones realistas de formatos
reales conocidos (Mercadona, Carrefour, Lidl, DIA, restaurantes, gasolineras),
escritas a mano para arrancar el desarrollo. **Deben ir sustituyéndose /
ampliándose con tickets REALES anonimizados** en cuanto la app funcione en
dispositivo: cada ticket real que falle se añade aquí (anonimizado: sin
direcciones exactas ni datos de tarjeta) junto con la regla que lo arregla.

`expected.json` solo compara las claves presentes (comparación parcial),
salvo `lines`, que cuando aparece se compara completa y en orden.
