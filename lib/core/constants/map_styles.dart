class MapStyles {
  MapStyles._();

  /// Premium muted map style — the one style every Sohr map uses.
  ///
  /// Flat neutral land, near-white low-saturation roads, subtle buildings and
  /// water, POIs and transit hidden, and only the labels needed to stay
  /// oriented (locality names, highway and arterial road names). Everything
  /// else is stripped so the pins that matter — store, drop, rider — read
  /// instantly against a quiet background.
  ///
  /// Styling is purely client-side rendering of tiles the map already fetched:
  /// it does not change what is billed. Map-load and API-call volume is what
  /// costs money, and that is controlled at the call sites, not here.
  static const String mutedGrey = r"""
[
  {"elementType":"geometry","stylers":[{"color":"#f4f4f4"}]},
  {"elementType":"labels.icon","stylers":[{"visibility":"off"}]},
  {"elementType":"labels.text.fill","stylers":[{"color":"#8a8a8a"}]},
  {"elementType":"labels.text.stroke","stylers":[{"color":"#f4f4f4"}]},
  {"featureType":"administrative","elementType":"geometry","stylers":[{"visibility":"off"}]},
  {"featureType":"administrative.land_parcel","stylers":[{"visibility":"off"}]},
  {"featureType":"administrative.neighborhood","stylers":[{"visibility":"off"}]},
  {"featureType":"administrative.locality","elementType":"labels.text.fill","stylers":[{"color":"#9a9a9a"}]},
  {"featureType":"landscape.man_made","elementType":"geometry","stylers":[{"color":"#ebebeb"}]},
  {"featureType":"landscape.natural","elementType":"geometry","stylers":[{"color":"#f0f1f0"}]},
  {"featureType":"poi","stylers":[{"visibility":"off"}]},
  {"featureType":"poi.park","elementType":"geometry","stylers":[{"color":"#e6e9e6"},{"visibility":"on"}]},
  {"featureType":"road","elementType":"labels.icon","stylers":[{"visibility":"off"}]},
  {"featureType":"road.local","elementType":"geometry","stylers":[{"color":"#ffffff"}]},
  {"featureType":"road.local","elementType":"labels","stylers":[{"visibility":"off"}]},
  {"featureType":"road.arterial","elementType":"geometry","stylers":[{"color":"#fafafa"}]},
  {"featureType":"road.arterial","elementType":"labels.text.fill","stylers":[{"color":"#a0a0a0"}]},
  {"featureType":"road.highway","elementType":"geometry","stylers":[{"color":"#ededed"}]},
  {"featureType":"road.highway","elementType":"geometry.stroke","stylers":[{"color":"#e2e2e2"}]},
  {"featureType":"road.highway","elementType":"labels.text.fill","stylers":[{"color":"#949494"}]},
  {"featureType":"transit","stylers":[{"visibility":"off"}]},
  {"featureType":"water","elementType":"geometry","stylers":[{"color":"#dde2e4"}]},
  {"featureType":"water","elementType":"labels.text","stylers":[{"visibility":"off"}]}
]
""";
}
