# Reparto por unidades físicas (P2.2)

## Contrato vigente

Una línea solo se descompone en unidades físicas cuando `quantityMilli` es un
múltiplo entero de 1000 y representa al menos dos unidades. Cantidades como
`0,466 kg`, `1,25 kg` o `750 ml` son una única línea compartible: no se inventan
unidades discretas a partir de decimales del OCR.

El modelo P2.2 es opt-in por línea:

```text
unitIds: [u0, u1]
assignment:
  type: units
  schemaVersion: 2
  units:
    u0: { participantA: true }
    u1: { participantA: true, participantB: true }
```

Los índices son estables dentro de la línea y no crean documentos adicionales.
Cada mapa de unidad contiene sus consumidores. Un mapa ausente o vacío significa
unidad no reclamada y recae íntegramente en el pagador real del ticket.

La app móvil muestra las unidades individualmente hasta 12 y usa una tira
horizontal compacta para cantidades mayores. La web conserva la misma semántica.
Ambos clientes actualizan una pertenencia mediante una ruta Firestore punteada;
dos personas que editan la misma unidad modifican campos distintos y no se pisan.
Rules verifica que el invitado solo cambie su pid y una unidad declarada en
`unitIds`.

## Redondeo determinista

1. El total de línea se divide entre las unidades con `allocateProportionally`
   y pesos iguales.
2. Cada importe de unidad se divide entre sus consumidores con la misma
   primitiva y pesos iguales.
3. Los empates entregan el céntimo al primer participante según el campo estable
   `order`; Dart y TypeScript consumen el mismo orden.
4. El total general del ticket se prorratea después sobre los consumos exactos de
   líneas, como antes de P2.2.

Así se mantienen siempre céntimos enteros, importes no negativos y las
invariantes `suma(unidad) == línea` y `suma(consumos) == ticket`.

Regresión de referencia: 2 × 2,09 €, unidad 1 para Edgar y unidad 2 compartida
por Edgar y Alba. Las unidades reciben 2,09 € cada una; la segunda se divide
1,05 €/1,04 € por orden estable. Resultado: Edgar 3,14 € y Alba 1,04 €.
Es el equivalente determinista permitido del reparto 3,13 €/1,05 € y mantiene
exactamente 4,18 €.

## Compatibilidad

- Datos históricos de línea completa: se leen con su contrato original.
- P2.1 sin `schemaVersion`: sus pesos siguen interpretándose exactamente como
  antes; no se recalculan balances históricos con otra semántica.
- P2.2: solo se activa si coinciden `type: units` y `schemaVersion: 2`.
- Editar una línea histórica ofrece una conversión explícita. Como los pesos
  antiguos no identifican qué unidad era compartida, la conversión comienza
  vacía y el usuario declara las unidades reales; no se adivina ni se migra en
  segundo plano.

El recompute autoritativo y el motor local usan el mismo contrato y los mismos
vectores dorados. La persistencia offline de Flutter conserva las escrituras
quirúrgicas; al reconectar, Firestore aplica las reglas y los triggers vuelven a
publicar el agregado autoritativo.
