import 'package:flutter/widgets.dart';

import '../../data/tour_dummy_data.dart';
import '../../models/tour.dart';

mixin TourStateMixin on ChangeNotifier {
  final List<TransportTour> tourItems = <TransportTour>[];
  String tourSearchQuery = '';
  TourStatus? tourStatusFilterValue;

  String get tourSearchQueryValue => tourSearchQuery;
  TourStatus? get tourStatusFilter => tourStatusFilterValue;

  bool get hasTourFilters =>
      tourSearchQuery.isNotEmpty || tourStatusFilterValue != null;

  List<TransportTour> get tours =>
      List<TransportTour>.unmodifiable(tourItems);

  List<TransportTour> get filteredTours {
    final query = tourSearchQuery.toLowerCase();
    return tourItems.where((tour) {
      final matchesStatus =
          tourStatusFilterValue == null || tour.status == tourStatusFilterValue;
      final matchesQuery = query.isEmpty ||
          tour.code.toLowerCase().contains(query) ||
          tour.driverName.toLowerCase().contains(query);
      return matchesStatus && matchesQuery;
    }).toList(growable: false);
  }

  int get activeToursCount => tourItems
      .where((tour) =>
          tour.status == TourStatus.inTransit ||
          tour.status == TourStatus.loading)
      .length;

  int get delayedToursCount =>
      tourItems.where((tour) => tour.status == TourStatus.delayed).length;

  int get completedToursCount =>
      tourItems.where((tour) => tour.status == TourStatus.completed).length;

  void initTours() {
    tourItems.addAll(buildDummyTours(DateTime.now()));
  }

  TransportTour? getTourById(String tourId) {
    for (final tour in tourItems) {
      if (tour.id == tourId) {
        return tour;
      }
    }
    return null;
  }

  List<TransportTour> getToursByWarehouse(String warehouseId) {
    return tourItems
        .where((tour) => tour.warehouseId == warehouseId)
        .toList(growable: false);
  }

  void setTourSearchQuery(String value) {
    tourSearchQuery = value;
    notifyListeners();
  }

  void setTourStatusFilter(TourStatus? status) {
    tourStatusFilterValue = status;
    notifyListeners();
  }

  void clearTourFilters() {
    tourSearchQuery = '';
    tourStatusFilterValue = null;
    notifyListeners();
  }
}
