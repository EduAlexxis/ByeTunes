import SwiftUI

struct SplashView: View {
    @State private var isAnimating = false
    @State private var opacity = 0.0
    
    var body: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea()
            
            VStack(spacing: 20) {
                ZStack {
                    Image("AppIconImage")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 120, height: 120)
                        .clipShape(RoundedRectangle(cornerRadius: 28))
                        .scaleEffect(isAnimating ? 1.0 : 0.8)
                }
                
                Text("ByeTunes")
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .tracking(1)
                    .opacity(opacity)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.8, dampingFraction: 0.6)) {
                isAnimating = true
            }
            withAnimation(.easeIn(duration: 1.0)) {
                opacity = 1.0
            }
        }
    }
}

#Preview {
    SplashView()
}
