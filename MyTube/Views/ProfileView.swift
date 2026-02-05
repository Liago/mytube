import SwiftUI

struct ProfileView: View {
    @StateObject private var cookieService = CookieStatusService.shared
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // User Info Card
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "person.circle.fill")
                                .resizable()
                                .frame(width: 50, height: 50)
                                .foregroundColor(.accentColor)
                            
                            VStack(alignment: .leading) {
                                Text("Utente Collegato")
                                    .font(.headline)
                                Text("Admin")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                        }
                    }
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(12)
                    
                    // Cookie Status Card
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Stato Cookies R2")
                            .font(.headline)
                        
                        if cookieService.isLoading {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        } else if let error = cookieService.errorMessage {
                            Text("Errore: \(error)")
                                .foregroundColor(.red)
                                .font(.caption)
                            
                            Button("Riprova") {
                                Task { await cookieService.fetchStatus() }
                            }
                        } else if let status = cookieService.status {
                            HStack {
                                Text("Stato:")
                                Spacer()
                                StatusBadge(status: status.status)
                            }
                            
                            Divider()
                            
                            HStack {
                                Text("Totale Cookies:")
                                Spacer()
                                Text("\(status.totalCookies)")
                                    .bold()
                            }
                            
                            HStack {
                                Text("Cookies Validi:")
                                Spacer()
                                Text("\(status.validCookies)")
                                    .foregroundColor(status.validCookies > 0 ? .primary : .red)
                            }
                            
                            if let expiration = status.earliestExpiration {
                                let date = Date(timeIntervalSince1970: expiration)
                                let daysLeft = Calendar.current.dateComponents([.day], from: Date(), to: date).day ?? 0
                                
                                Divider()
                                
                                HStack {
                                    Text("Prossima Scadenza:")
                                    Spacer()
                                    VStack(alignment: .trailing) {
                                        Text(date, style: .date)
                                        Text(daysLeft > 0 ? "Tra \(daysLeft) giorni" : "Scaduto")
                                            .font(.caption)
                                            .foregroundColor(daysLeft < 3 ? .red : .secondary)
                                    }
                                }
                            }
                            
                        } else {
                            Text("Nessun dato disponibile")
                                .foregroundColor(.secondary)
                            Button("Carica Dati") {
                                Task { await cookieService.fetchStatus() }
                            }
                        }
                    }
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(12)
                    
                    // Instructions
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Istruzioni", systemImage: "info.circle")
                            .font(.headline)
                        
                        Text("Per aggiornare i cookies:")
                            .font(.subheadline)
                        Text("1. Estrai i cookies da YouTube (Netscape format).")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("2. Salva il file come `_cookies.json`.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("3. Carica il file nel bucket R2 `mytube-audio`.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(12)
                    
                    Spacer()
                }
                .padding()
            }
            .navigationTitle("Profilo")
            .refreshable {
                await cookieService.fetchStatus()
            }
            .task {
                if cookieService.status == nil {
                    await cookieService.fetchStatus()
                }
            }
        }
    }
}

struct StatusBadge: View {
    let status: String
    
    var color: Color {
        switch status {
        case "Valid": return .green
        case "Expiring Soon": return .yellow
        case "Expired", "Missing": return .red
        default: return .gray
        }
    }
    
    var body: some View {
        Text(status)
            .font(.caption)
            .fontWeight(.bold)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.2))
            .foregroundColor(color)
            .cornerRadius(8)
    }
}

#Preview {
    ProfileView()
}
