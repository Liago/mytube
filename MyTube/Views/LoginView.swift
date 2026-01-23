import SwiftUI

struct LoginView: View {
    @ObservedObject var authManager = AuthManager.shared
    
    var body: some View {
        VStack {
            Spacer()
            
            Image(systemName: "play.circle.fill")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 100, height: 100)
                .foregroundColor(.red)
                .padding(.bottom, 20)
            
            Text("Welcome to MyTube")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            Text("Listen to your YouTube favorites in background.")
                .font(.subheadline)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
                .padding(.bottom, 40)
            
            if let error = authManager.errorMessage {
                Text(error)
                    .foregroundColor(.red)
                    .font(.caption)
                    .padding()
            }
            
            Button(action: {
                authManager.signIn()
            }) {
                HStack {
                    Image(systemName: "g.circle.fill") // Placeholder for G logo
                    Text("Sign in with Google")
                }
                .font(.headline)
                .foregroundColor(.white)
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color.blue)
                .cornerRadius(10)
            }
            .padding(.horizontal, 40)
            
            Spacer()
        }
    }
}
