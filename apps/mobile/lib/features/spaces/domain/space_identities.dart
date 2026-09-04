/// Cuándo un contexto puede repartir un gasto (BUG-6).
///
/// La pregunta no es cuántas CUENTAS hay, sino cuántas PERSONAS. Contar
/// documentos de membresía dejaba fuera a quien no tiene app: un grupo con
/// Edgar y Pablo (MANUAL) tiene dos identidades económicas y podía repartir
/// perfectamente, pero la app pedía una segunda cuenta que nadie iba a crear.
library;

import 'package:domain/domain.dart' show effectiveEconomicIdentities;

import 'space_models.dart';

/// Personas distintas incorporadas al espacio, ya colapsadas: un MANUAL
/// vinculado y su cuenta cuentan UNA vez (ADR-037).
///
/// Solo mira lo que YA está dentro. Una invitación pendiente reserva una
/// plaza pero no incorpora a nadie, así que no suma — por eso no se leen
/// aquí las invitaciones.
List<String> spaceEconomicIdentities({
  required List<SpaceMember> members,
  required List<ManualParticipant> manuals,
}) => effectiveEconomicIdentities(
  accountUids: members.map((member) => member.uid),
  manualLinks: {for (final manual in manuals) manual.id: manual.linkedUid},
);

/// ¿Hay gente suficiente para repartir un gasto?
///
/// Repartir exige DOS personas: con una sola no hay nada que repartir. Una
/// RELACIÓN son exactamente dos por definición, así que mientras la segunda
/// no esté incorporada —una v2 con la invitación sin aceptar— no opera.
///
/// Un GRUPO admite de dos en adelante. Antes exigía tres, que es cuántas
/// personas justifican CREAR un grupo en vez de una relación (ADR-030), no
/// cuántas hacen falta para partir una cuenta; y esa confusión bloqueaba el
/// caso real de compartir gastos con alguien sin cuenta, porque una relación
/// con MANUAL era hasta hace poco imposible. Un grupo también encoge: que se
/// vaya el tercero no invalida los gastos entre los dos que quedan.
bool contextReadyForExpenses(SpaceKind kind, int identities) =>
    kind == SpaceKind.relationship ? identities == 2 : identities >= 2;
