//
//  GymMapView.swift
//  AnyGym
//
//  Created on iOS App
//

import SwiftUI
import MapKit
import CoreLocation

struct GymMapView: UIViewRepresentable {
    let gyms: [Gym]
    @Binding var region: MKCoordinateRegion
    
    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.setRegion(region, animated: false)
        mapView.showsUserLocation = true
        return mapView
    }
    
    func updateUIView(_ mapView: MKMapView, context: Context) {
        mapView.setRegion(region, animated: true)
        
        // Remove existing annotations
        mapView.removeAnnotations(mapView.annotations.filter { !($0 is MKUserLocation) })
        
        // Group gyms by location and create cluster annotations
        let groupedGyms = Dictionary(grouping: gyms) { gym -> String in
            // Round coordinates to create clusters (approximately 0.1 degree = ~11km)
            let lat = round(gym.latitude * 10) / 10
            let lon = round(gym.longitude * 10) / 10
            return "\(lat),\(lon)"
        }
        
        // Add annotations for each cluster
        for (_, gymGroup) in groupedGyms {
            if let firstGym = gymGroup.first {
                let count = gymGroup.count
                let annotation = GymClusterAnnotation(
                    coordinate: firstGym.coordinate,
                    gymCount: count
                )
                mapView.addAnnotation(annotation)
            }
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class Coordinator: NSObject, MKMapViewDelegate {
        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard let gymAnnotation = annotation as? GymClusterAnnotation else {
                return nil
            }
            
            let identifier = "GymCluster"
            var annotationView = mapView.dequeueReusableAnnotationView(withIdentifier: identifier)
            
            if annotationView == nil {
                annotationView = MKAnnotationView(annotation: annotation, reuseIdentifier: identifier)
                annotationView?.canShowCallout = false
                
                // Create custom view with orange circle and count
                let circleView = UIView(frame: CGRect(x: 0, y: 0, width: 50, height: 50))
                circleView.backgroundColor = UIColor.systemOrange
                circleView.layer.cornerRadius = 25
                circleView.layer.borderWidth = 2
                circleView.layer.borderColor = UIColor.white.cgColor
                
                let label = UILabel(frame: CGRect(x: 0, y: 0, width: 50, height: 50))
                label.text = "\(gymAnnotation.gymCount)"
                label.textColor = .white
                label.font = UIFont.boldSystemFont(ofSize: 16)
                label.textAlignment = .center
                label.tag = 100 // Tag to find and update later
                
                circleView.addSubview(label)
                annotationView?.addSubview(circleView)
                annotationView?.frame = circleView.frame
            } else {
                annotationView?.annotation = annotation
                // Update the count label
                if let circleView = annotationView?.subviews.first,
                   let label = circleView.subviews.first(where: { $0.tag == 100 }) as? UILabel {
                    label.text = "\(gymAnnotation.gymCount)"
                }
            }
            
            return annotationView
        }
    }
}

class GymClusterAnnotation: NSObject, MKAnnotation {
    var coordinate: CLLocationCoordinate2D
    var gymCount: Int
    
    init(coordinate: CLLocationCoordinate2D, gymCount: Int) {
        self.coordinate = coordinate
        self.gymCount = gymCount
    }
}

