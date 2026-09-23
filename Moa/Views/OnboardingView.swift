import SwiftUI

/// Shown once on first launch, and any time from the "앱 소개" toolbar button.
/// Explains what the host does with the app before asking for photo and network permissions.
struct OnboardingView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var page = 0

    private var pages: [Page] {
        // Built as a String so the iCloud sentence is only claimed when remote sending is on.
        var arrival = String(localized: "이벤트를 열면 QR이 나오고, 그동안 사진이 들어와요. 같은 Wi-Fi에 있는 사람은 이 iPhone으로 바로 보내요.")
        if RemoteTransfer.isConfigured {
            arrival += " " + String(localized: "멀리 있는 사람이 보낸 사진은 iCloud를 거쳐 들어와요.")
        }
        let howItArrives = Page(symbol: "wifi", title: "이 화면을 열어 둔 동안 받아요", body: arrival)

        return [
            Page(
                symbol: "qrcode",
                title: "QR 하나로 사진을 모아요",
                body: String(localized: "행사에서 QR을 보여주기만 하면 돼요. 사진을 보내는 사람은 앱을 설치하지 않고, 카메라로 QR을 찍어서 바로 보낼 수 있어요.")
            ),
            Page(
                symbol: "photo.on.rectangle.angled",
                title: "원본 그대로, 찍은 시각 그대로",
                body: String(localized: "받은 사진은 이 iPhone의 사진 앱에 들어가요. 내가 찍은 사진처럼 촬영한 날짜 자리에 놓이고, 이벤트 이름의 앨범에도 정리돼요.")
            ),
            howItArrives,
        ]
    }

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                ForEach(Array(pages.enumerated()), id: \.offset) { index, page in
                    PageView(page: page)
                        .tag(index)
                }
            }
            .tabViewStyle(.page)
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            Button {
                if isLastPage {
                    dismiss()
                } else {
                    withAnimation { page += 1 }
                }
            } label: {
                Text(isLastPage ? "시작하기" : "다음")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
        .overlay(alignment: .topTrailing) {
            if !isLastPage {
                Button("건너뛰기") { dismiss() }
                    .padding(.trailing, 20)
                    .padding(.top, 12)
            }
        }
    }

    private var isLastPage: Bool { page == pages.count - 1 }

    fileprivate struct Page {
        let symbol: String
        let title: LocalizedStringKey
        let body: String
    }
}

private struct PageView: View {
    let page: OnboardingView.Page

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: page.symbol)
                .font(.system(size: 88))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)

            VStack(spacing: 16) {
                Text(page.title)
                    .font(.title.bold())
                    .multilineTextAlignment(.center)

                Text(page.body)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 32)

            Spacer()
        }
    }
}

#Preview {
    OnboardingView()
}
