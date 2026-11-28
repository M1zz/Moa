import SwiftUI
import LeeoKit

/// Shown once on first launch, and any time from the "앱 소개" toolbar button.
/// Explains shared albums before asking for photo and network permissions.
struct OnboardingView: View {
    @Environment(\.dismiss) private var dismiss
    /// 첫 안내의 결과를 한 번만 보낸다. 물음표 단추로 다시 본 안내는 세지 않는다.
    @AppStorage("onboardingReported") private var onboardingReported = false
    @State private var page = 0

    private var pages: [Page] {
        [
            Page(
                symbol: "link",
                title: "링크 하나로 멤버가 돼요",
                body: String(localized: "공유 앨범마다 사람을 한 명씩 추가할 필요가 없어요. 링크를 보내거나 QR을 보여주면, 연 사람은 바로 멤버가 돼요. 멤버 누구나 다른 사람을 초대할 수 있어요.")
            ),
            Page(
                symbol: "rectangle.stack.badge.person.crop",
                title: "앨범을 여러 개 두고 써요",
                body: String(localized: "가족, 여행, 모임마다 앨범을 만들어 두세요. 누가 들어와 있는지 보이고, 언제든 사진을 보탤 수 있어요. 앱이 없는 사람도 카메라로 QR을 찍어 바로 보낼 수 있어요.")
            ),
            Page(
                symbol: "photo.on.rectangle.angled",
                title: "원본 그대로, 찍은 시각 그대로",
                body: String(localized: "멤버가 올린 사진은 각자의 사진 앱에 원본 그대로 들어가요. 내가 찍은 사진처럼 촬영한 날짜 자리에 놓이고, 같은 이름의 앨범에도 정리돼요.")
            ),
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
                    finish(skipped: false)
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
                Button("건너뛰기") { finish(skipped: true) }
                    .padding(.trailing, 20)
                    .padding(.top, 12)
            }
        }
    }

    private func finish(skipped: Bool) {
        if !onboardingReported {
            onboardingReported = true
            LeeoAnalyticsCenter.track(.custom(name: skipped ? "onboarding_skipped" : "onboarding_completed", parameters: [:]))
        }
        dismiss()
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
