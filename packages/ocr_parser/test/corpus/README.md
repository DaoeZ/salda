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

**Lo que el corpus NO puede expresar** son las señales: la confianza de una
línea y el margen con el que un ticket se considera cuadrado. Eso vive en
`test/es_receipt_parser_test.dart`, y no es un detalle: un ticket que cuadra
al céntimo puede estar mal leído (ver A12/A15 en la Biblia), así que las
señales son lo único que avisa de ello.
