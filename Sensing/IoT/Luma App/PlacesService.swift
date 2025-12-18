//
//  PlacesService.swift
//  LumaHelmet
//
//  Lightweight place search using MapKit - iOS 17+
//

import Foundation
import Combine
import MapKit
import CoreLocation

struct PlaceSuggestion: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let coordinate: CLLocationCoordinate2D
}

@MainActor
final class PlacesService: ObservableObject {
    @Published var suggestions: [PlaceSuggestion] = []
    private var currentSearchTask: Task<Void, Never>?
    
    func searchPlaces(query: String, near location: CLLocation?) {
        // Cancel any in-flight search
        currentSearchTask?.cancel()
        
        // Clear if query is empty
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            suggestions.removeAll()
            return
        }
        
        currentSearchTask = Task { [weak self] in
            guard let self else { return }
            
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = trimmed
            
            if let location = location {
                // Bias results around the current location
                let span = MKCoordinateSpan(latitudeDelta: 0.15, longitudeDelta: 0.15)
                request.region = MKCoordinateRegion(center: location.coordinate, span: span)
            }
            
            let search = MKLocalSearch(request: request)
            do {
                let response = try await search.start()
                let items = response.mapItems
                
                // Map to suggestions
                let mapped: [PlaceSuggestion] = items.compactMap { item in
                    guard let coord = item.placemark.location?.coordinate else { return nil }
                    let title = item.name ?? "Unnamed place"
                    let subtitle = item.placemark.title ?? item.placemark.subtitle ?? ""
                    return PlaceSuggestion(title: title, subtitle: subtitle, coordinate: coord)
                }
                
                // Update on main actor
                self.suggestions = Array(mapped.prefix(12))
            } catch {
                // Ignore cancellations; clear results on other errors
                if Task.isCancelled { return }
                self.suggestions.removeAll()
                print("PlacesService: search error - \(error.localizedDescription)")
            }
        }
    }
    
    func clearSuggestions() {
        currentSearchTask?.cancel()
        suggestions.removeAll()
    }
}
