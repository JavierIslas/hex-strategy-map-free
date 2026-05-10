class_name FogState
## Estados de niebla de guerra.
##
## Enum compartido por HexCell (almacenamiento) y FogOfWar (lógica de revelado).
## Usar como entero ordinario en match/comparaciones — no requiere instanciar nada.
##   HIDDEN   → hex nunca visto por el jugador (oscuridad total).
##   EXPLORED → hex visto en el pasado pero fuera del rango actual (sombra parcial).
##   VISIBLE  → dentro del rango de visión actual (completamente revelado).

enum { HIDDEN, EXPLORED, VISIBLE }
