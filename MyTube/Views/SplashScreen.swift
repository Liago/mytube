import SwiftUI

struct SplashScreen: View {
    var body: some View {
        ZStack {
            // Gradient Background
            LinearGradient(
                gradient: Gradient(colors: [Color.black, Color(UIColor.darkGray)]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .edgesIgnoringSafeArea(.all)
            
            VStack {
                Spacer()
                
                // Icon (using system image for now, similar to Play button)
                Image(systemName: "play.circle.fill")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 100, height: 100)
                    .foregroundColor(.red)
                    .shadow(color: .red.opacity(0.5), radius: 10, x: 0, y: 5)
                
                // Title
                Text("TubeCast")
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .padding(.top, 20)
                
                Text("Your YouTube Audio Companion")
                    .font(.subheadline)
                    .foregroundColor(.gray)
                    .padding(.top, 5)
                
                Spacer()
                
                // Loading Indicator at bottom
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .padding(.bottom, 50)
            }
        }
    }
}

struct SplashScreen_Previews: PreviewProvider {
    static var previews: some View {
        SplashScreen()
    }
}
