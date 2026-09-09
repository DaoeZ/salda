/// Quién puede ACTUAR económicamente en nombre de un actor (ADR-038).
///
/// El principio de producto es uno solo: **el receptor del dinero es quien
/// confirma que lo ha recibido**. Ser administrador o propietario de un
/// espacio no otorga esa capacidad — si lo hiciera, un tercero podría dar por
/// saldada una deuda ajena y el balance de una persona registrada dependería
/// de la buena fe de otra.
///
/// La única excepción es la que el producto necesita para funcionar: un
/// participante MANUAL (ADR-033) no tiene cuenta, ni dispositivo, ni forma de
/// confirmar nada. Sin representante, un cobro dirigido a él jamás podría
/// cerrarse. Por eso —y solo entonces— el propietario o un administrador del
/// espacio que custodia esa identidad puede actuar por él.
///
/// La representación es TEMPORAL por construcción: en cuanto el manual se
/// vincula a una cuenta (ADR-037, `linkedUid`), quien decide es esa cuenta y
/// el administrador deja de poder actuar en su nombre. No hay que revocar
/// nada, porque nunca fue un permiso concedido sino la ausencia de alguien
/// capaz de ejercerlo.
library;

import 'economic_actor.dart';

/// Con qué título actúa alguien sobre las cuentas de un actor económico.
enum EconomicActingRole {
  /// Es esa persona: su cuenta, o la cuenta a la que se vinculó ese manual.
  self,

  /// Actúa POR una identidad sin cuenta que no puede hacerlo ella misma.
  representative,

  /// No puede actuar.
  none,
}

/// Título con el que [viewerUid] puede actuar sobre lo que corresponde a
/// [actor].
///
/// [viewerIsSpaceAdmin] es la autoridad ya resuelta sobre el espacio que
/// custodia al manual (propietario o administrador). Nunca se deduce aquí: es
/// un hecho del contexto y lo verifica también Firestore Rules, que es la
/// autoridad real.
///
/// [linkedUid] es la cuenta a la que se vinculó el participante manual, si ya
/// lo está.
EconomicActingRole economicActingRole({
  required String actor,
  required String viewerUid,
  bool viewerIsSpaceAdmin = false,
  String? linkedUid,
}) {
  if (actor.isEmpty || viewerUid.isEmpty) return EconomicActingRole.none;

  // Una cuenta responde siempre por sí misma. Aquí es donde se cierra la
  // puerta a que un administrador toque el saldo de un usuario registrado.
  if (isAccountActor(actor)) {
    return actor == viewerUid
        ? EconomicActingRole.self
        : EconomicActingRole.none;
  }

  // Manual ya vinculado: manda su cuenta y la representación se acabó.
  if (linkedUid != null && linkedUid.isNotEmpty) {
    return linkedUid == viewerUid
        ? EconomicActingRole.self
        : EconomicActingRole.none;
  }

  return viewerIsSpaceAdmin
      ? EconomicActingRole.representative
      : EconomicActingRole.none;
}

/// ¿Puede [viewerUid] confirmar que se ha RECIBIDO un cobro dirigido a
/// [creditorActor]?
bool canConfirmReceipt({
  required String creditorActor,
  required String viewerUid,
  bool viewerIsSpaceAdmin = false,
  String? linkedUid,
}) =>
    economicActingRole(
      actor: creditorActor,
      viewerUid: viewerUid,
      viewerIsSpaceAdmin: viewerIsSpaceAdmin,
      linkedUid: linkedUid,
    ) !=
    EconomicActingRole.none;
