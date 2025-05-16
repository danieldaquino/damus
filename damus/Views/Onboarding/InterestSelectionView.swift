//
//  InterestSelectionView.swift
//  damus
//
//  Created by Daniel D’Aquino on 2025-05-16.
//
import SwiftUI

extension OnboardingSuggestionsView {
    
    struct InterestSelectionView: View {
        var model: SuggestedUsersViewModel
        var next_page: (() -> Void)
        // Hard-coded list of interest topics
        private let availableInterests = [
            NSLocalizedString("Music", comment: "Interest"),
            NSLocalizedString("Sports", comment: "Interest"),
            NSLocalizedString("Art", comment: "Interest"),
            NSLocalizedString("Technology", comment: "Interest"),
            NSLocalizedString("Travel", comment: "Interest"),
            NSLocalizedString("Food", comment: "Interest"),
            NSLocalizedString("Movies", comment: "Interest"),
            NSLocalizedString("Health", comment: "Interest")
        ]
        
        // Track selected interests using a Set
        @State private var selectedInterests: Set<String> = []
        // Track navigation for the next step
        @State private var isNavigating = false
        
        // Validate that the user has selected between 2 and 4 interests
        private var isNextEnabled: Bool {
            let count = selectedInterests.count
            return count >= 2 && count <= 4
        }
        
        var body: some View {
            VStack(spacing: 20) {
                // Title
                Text(NSLocalizedString("Select Your Interests", comment: "Screen title for interest selection"))
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)
                    .padding(.top)
                
                // Instruction subtitle
                Text(NSLocalizedString("Please pick between 2 and 4 interests", comment: "Instruction for interest selection"))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                
                // Interests grid view
                InterestsGridView(availableInterests: availableInterests,
                                  selectedInterests: $selectedInterests)
                .padding()
                
                Spacer()
                
                // Next button wrapped inside a NavigationLink for easy transition.
                Button(action: {
                    self.next_page()
                }, label: {
                    Text(NSLocalizedString("Next", comment: "Next button title"))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(isNextEnabled ? Color.blue : Color.gray)
                        .cornerRadius(8)
                })
                .disabled(!isNextEnabled)
                .padding([.leading, .trailing, .bottom])
            }
            .padding()
        }
    }
    
    // A grid view to display interest options
    struct InterestsGridView: View {
        let availableInterests: [String]
        @Binding var selectedInterests: Set<String>
        
        // Adaptive grid layout with two columns
        private let columns = [
            GridItem(.flexible()),
            GridItem(.flexible())
        ]
        
        var body: some View {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(availableInterests, id: \ .self) { interest in
                    InterestButton(interest: interest,
                                   isSelected: selectedInterests.contains(interest)) {
                        // Toggle selection
                        if selectedInterests.contains(interest) {
                            selectedInterests.remove(interest)
                        } else if selectedInterests.count < 4 {
                            selectedInterests.insert(interest)
                        }
                    }
                }
            }
        }
    }
    
    // A button view representing a single interest option
    struct InterestButton: View {
        let interest: String
        let isSelected: Bool
        var action: () -> Void
        
        var body: some View {
            Button(action: action) {
                Text(interest)
                    .font(.body)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(isSelected ? Color.blue : Color.gray.opacity(0.2))
                    .foregroundColor(isSelected ? Color.white : Color.primary)
                    .cornerRadius(8)
            }
        }
    }
}

struct InterestSelectionView_Previews: PreviewProvider {
    static var previews: some View {
        OnboardingSuggestionsView.InterestSelectionView(
            model: SuggestedUsersViewModel(damus_state: test_damus_state),
            next_page: { print("next") }
        )
    }
}
