//
//  GPT4VisionAPI.swift
//  Custom Camera
//
//  Created by Hao Mei on 2/9/24.
//

import Foundation
import UIKit

class GPT4VisionAPI {

    let apiURL = URL(string: "https://oneapi.xty.app/v1/chat/completions")!
    let apiKey = "ENTER YOUR API"

    func callGPT4VisionAPI(with image: UIImage, completion: @escaping (String?) -> Void) {
        // Convert the image to base64
        guard let imageData = image.jpegData(compressionQuality: 1.0) else {
            print("Failed to convert image to data.")
            completion(nil)
            return
        }

        let base64Image = imageData.base64EncodedString(options: .lineLength64Characters)

        // Set up the request
        var request = URLRequest(url: apiURL)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        // Prepare the request payload with base64 image
        let payload: [String: Any] = [
            "model": "gpt-4-vision-preview",
            "messages": [
                [
                    "role": "user",
                    "content": [
                        [
                            "type": "text",
                            "text": "I am blind. Concisely describe this scene in front of me. Focus on information critical for the visually impaired."
                        ],
                        [
                            "type": "image_url",
                            "image_url": [
                                "url": "data:image/jpeg;base64,\(base64Image)"
                            ]
                        ]
                    ]
                ]
            ],
            "max_tokens": 300
        ]

        // Convert payload to JSON data
        guard let jsonData = try? JSONSerialization.data(withJSONObject: payload) else {
            print("Failed to serialize JSON data.")
            completion(nil)
            return
        }

        // Attach JSON data to the request
        request.httpBody = jsonData

        // Make the network request
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("Error: \(error.localizedDescription)")
                completion(nil)
                return
            }

            guard let data = data else {
                print("No data received.")
                completion(nil)
                return
            }
//            do {
//                let tempResponse = try JSONSerialization.jsonObject(with: data, options: [])
//                print("API response: \(tempResponse)")
//            } catch {
//                print("Error deserializing")
//            }
            
                

            // Handle the API response data
            do {
                // Parse the JSON data
                if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
                   let choices = json["choices"] as? [[String: Any]],
                   let firstChoice = choices.first,
                   let message = firstChoice["message"] as? [String: String],
                   let content = message["content"] {
                    // Here you have the content string
                    completion(content)
                }
            } catch {
                print("Failed to parse JSON: \(error.localizedDescription)")
                completion(nil)
            }
        }

        task.resume()
    }
}
