//
//  ImageCarousel.swift
//  damus
//
//  Created by William Casarin on 2022-10-16.
//

import SwiftUI
import Kingfisher
import Combine

// TODO: all this ShareSheet complexity can be replaced with ShareLink once we update to iOS 16
struct ShareSheet: UIViewControllerRepresentable {
    typealias Callback = (_ activityType: UIActivity.ActivityType?, _ completed: Bool, _ returnedItems: [Any]?, _ error: Error?) -> Void
    
    let activityItems: [URL?]
    let callback: Callback? = nil
    let applicationActivities: [UIActivity]? = nil
    let excludedActivityTypes: [UIActivity.ActivityType]? = nil
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(
            activityItems: activityItems as [Any],
            applicationActivities: applicationActivities)
        controller.excludedActivityTypes = excludedActivityTypes
        controller.completionWithItemsHandler = callback
        return controller
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {
        // nothing to do here
    }
}

//  Custom UIPageControl
struct PageControlView: UIViewRepresentable {
    @Binding var currentPage: Int
    var numberOfPages: Int
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> UIPageControl {
        let uiView = UIPageControl()
        uiView.backgroundStyle = .minimal
        uiView.currentPageIndicatorTintColor = UIColor(Color("DamusPurple"))
        uiView.pageIndicatorTintColor = UIColor(Color("DamusLightGrey"))
        uiView.currentPage = currentPage
        uiView.numberOfPages = numberOfPages
        uiView.addTarget(context.coordinator, action: #selector(Coordinator.valueChanged), for: .valueChanged)
        return uiView
    }

    func updateUIView(_ uiView: UIPageControl, context: Context) {
        uiView.currentPage = currentPage
        uiView.numberOfPages = numberOfPages
    }
}

extension PageControlView {
    final class Coordinator: NSObject {
        var parent: PageControlView
        
        init(_ parent: PageControlView) {
            self.parent = parent
        }
        
        @objc func valueChanged(sender: UIPageControl) {
            let currentPage = sender.currentPage
            withAnimation {
                parent.currentPage = currentPage
            }
        }
    }
}


enum ImageShape {
    case square
    case landscape
    case portrait
    case unknown
    
    static func determine_image_shape(_ size: CGSize) -> ImageShape {
        guard size.height > 0 else {
            return .unknown
        }
        let imageRatio = size.width / size.height
        switch imageRatio {
            case 1.0: return .square
            case ..<1.0: return .portrait
            case 1.0...: return .landscape
            default: return .unknown
        }
    }
}

// TODO: Restore caching

/// The `CarouselModel` helps `ImageCarousel` with some state management logic, keeping track of media sizes, and the ideal display size
///
/// This model is necessary because the state management logic required to keep track of media sizes for each one of the carousel items,
/// and the ideal display size at each moment is not a trivial task.
///
/// The rules for the media fill are as follows:
///  1. The media item should generally have a width that completely fills the width of its parent view
///  2. The height of the carousel should be adjusted accordingly
///  3. The only exception to rules 1 and 2 is when the total height would be 20% larger than the height of the device
///  4. If none of the above can be computed (e.g. due to missing information), default to a reasonable height, where the media item will fit into.
///
/// ## Usage notes
///
/// The view is has the following state management responsibilities:
///  1. Watching the size of the images (we have no mechanism to do this from `CarouselModel` and setting the new size to `media_size_information`
///  2. Notifying this class of geometry reader changes, by setting `geo_size`
///
/// ## Implementation notes
///
/// This class is organized in a way to reduce stateful behavior and the transiency bugs it can cause.
///
/// This is accomplished through the following pattern:
/// 1. The `current_item_fill` is a published property so that any updates instantly re-render the view
/// 2. However, `current_item_fill` has a mathematical dependency on other members of this class
/// 3. Therefore, the members on which the fill property depends on all have `didSet` observers that will cause the `current_item_fill` to be recalculated and published.
///
@MainActor
class CarouselModel: ObservableObject {
    // MARK: Immutable object attributes
    // These are some attributes that are not expected to change throughout the lifecycle of this object
    
    let damus_state: DamusState
    let urls: [MediaUrl]
    let default_fill_height: CGFloat
    let max_height: CGFloat
    
    
    // MARK: Miscellaneous
    
    private var all_cancellables: [AnyCancellable] = []
    
    
    // MARK: State management properties
    // Properties relevant to state management.

    /// Stores information about the size of each media item in `urls`.
    /// **Usage note:** The view is responsible for setting the size of image urls
    var media_size_information: [URL: CGSize] {
        didSet {
            guard let current_url else { return }
            // Upon updating information, update the carousel fill size if the size for the current url has changed
            if oldValue[current_url] != media_size_information[current_url] {
                self.refresh_current_item_fill()
            }
        }
    }
    /// Stores information about the geometry reader
    var geo_size: CGSize? {
        didSet { self.refresh_current_item_fill() }
    }
    @Published var selectedIndex: Int {
        didSet { self.refresh_current_item_fill() }
    }
    var current_url: URL? {
        return urls[safe: selectedIndex]?.url
    }
    @Published var current_item_fill: ImageFill?
    
    
    // MARK: Initialization and de-initialization

    init(damus_state: DamusState, urls: [MediaUrl]) {
        self.damus_state = damus_state
        self.urls = urls
        self.default_fill_height = 350
        self.max_height = UIScreen.main.bounds.height * 1.2 // 1.2
        self.selectedIndex = 0
        self.current_item_fill = nil
        self.geo_size = nil
        self.media_size_information = [:]
        self.observe_video_sizes()
        // Compute remaining states
        Task {
            self.refresh_current_item_fill()
        }
    }
    
    private func observe_video_sizes() {
        for media_url in urls {
            switch media_url {
                case .video(let url):
                    let video_player = damus_state.video.get_player(for: url)
                    if let video_size = video_player.video_size {
                        self.media_size_information[url] = video_size
                    }
                    let observer_cancellable = video_player.$video_size.sink(receiveValue: { new_size in
                        self.media_size_information[url] = new_size
                    })
                    all_cancellables.append(observer_cancellable)
                case .image(_):
                    break;  // Observing an image size needs to be done on the view directly, through the `.observe_image_size` modifier
            }
        }
    }
    
    deinit {
        for cancellable_item in all_cancellables {
            cancellable_item.cancel()
        }
    }
    
    // MARK: State management and logic

    private func refresh_current_item_fill() {
        if let current_url,
           let item_size = self.media_size_information[current_url],
           let geo_size {
            self.current_item_fill = ImageFill.calculate_image_fill(
                geo_size: geo_size,
                img_size: item_size,
                maxHeight: self.max_height,
                fillHeight: self.default_fill_height
            )
        }
        else {
            // Not enough information to compute the proper fill. Default to nil
            self.current_item_fill = nil
        }
    }
}

// MARK: - Image Carousel
@MainActor
struct ImageCarousel<Content: View>: View {
    let evid: NoteId
    @ObservedObject var model: CarouselModel
    let content: ((_ dismiss: @escaping (() -> Void)) -> Content)?

    init(state: DamusState, evid: NoteId, urls: [MediaUrl]) {
        self.evid = evid
        self._model = ObservedObject(initialValue: CarouselModel(damus_state: state, urls: urls))
        self.content = nil
    }
    
    init(state: DamusState, evid: NoteId, urls: [MediaUrl], @ViewBuilder content: @escaping (_ dismiss: @escaping (() -> Void)) -> Content) {
        self.evid = evid
        self._model = ObservedObject(initialValue: CarouselModel(damus_state: state, urls: urls))
        self.content = content
    }
    
    var filling: Bool {
        model.current_item_fill?.filling == true
    }
    
    var height: CGFloat {
        model.current_item_fill?.height ?? model.default_fill_height
    }
    
    func Placeholder(url: URL, geo_size: CGSize, num_urls: Int) -> some View {
        Group {
            if num_urls > 1 {
                // jb55: quick hack since carousel with multiple images looks horrible with blurhash background
                Color.clear
            } else if let meta = model.damus_state.events.lookup_img_metadata(url: url),
               case .processed(let blurhash) = meta.state {
                Image(uiImage: blurhash)
                    .resizable()
                    .frame(width: geo_size.width * UIScreen.main.scale, height: self.height * UIScreen.main.scale)
            } else {
                Color.clear
            }
        }
    }
    
    func Media(geo: GeometryProxy, url: MediaUrl, index: Int) -> some View {
        Group {
            switch url {
            case .image(let url):
                Img(geo: geo, url: url, index: index)
                    .onTapGesture {
                        present(full_screen_item: .full_screen_carousel(urls: model.urls, selectedIndex: $model.selectedIndex))
                    }
            case .video(let url):
                    let video_model = model.damus_state.video.get_player(for: url)
                    DamusVideoPlayerView(
                        model: video_model,
                        coordinator: model.damus_state.video,
                        style: .preview(on_tap: {
                            present(full_screen_item: .full_screen_carousel(urls: model.urls, selectedIndex: $model.selectedIndex))
                        })
                    )
            }
        }
    }
    
    func Img(geo: GeometryProxy, url: URL, index: Int) -> some View {
        KFAnimatedImage(url)
            .callbackQueue(.dispatch(.global(qos:.background)))
            .backgroundDecode(true)
            .imageContext(.note, disable_animation: model.damus_state.settings.disable_animation)
            .image_fade(duration: 0.25)
            .cancelOnDisappear(true)
            .configure { view in
                view.framePreloadCount = 3
            }
            .observe_image_size(size_changed: { size in
                model.media_size_information[url] = size
            })
            .background {
                Placeholder(url: url, geo_size: geo.size, num_urls: model.urls.count)
            }
            .aspectRatio(contentMode: filling ? .fill : .fit)
            .kfClickable()
            .position(x: geo.size.width / 2, y: geo.size.height / 2)
            .tabItem {
                Text(url.absoluteString)
            }
            .id(url.absoluteString)
            .padding(0)
                
    }
    
    var Medias: some View {
        TabView(selection: $model.selectedIndex) {
            ForEach(model.urls.indices, id: \.self) { index in
                GeometryReader { geo in
                    Media(geo: geo, url: model.urls[index], index: index)
                        .onChange(of: geo.size, perform: { new_size in
                            model.geo_size = new_size
                        })
                        .onAppear {
                            model.geo_size = geo.size
                        }
                }
            }
        }
        .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
        .frame(height: height)
        .onChange(of: model.selectedIndex) { value in
            model.selectedIndex = value
        }
    }
    
    var body: some View {
        VStack {
            if #available(iOS 18.0, *) {
                Medias
            } else {
                // An empty tap gesture recognizer is needed on iOS 17 and below to suppress other overlapping tap recognizers
                // Otherwise it will both open the carousel and go to a note at the same time
                Medias.onTapGesture { }
            }
            
            
            if model.urls.count > 1 {
                PageControlView(currentPage: $model.selectedIndex, numberOfPages: model.urls.count)
                    .frame(maxWidth: 0, maxHeight: 0)
                    .padding(.top, 5)
            }
        }
    }
}

// MARK: - Image Modifier
extension KFOptionSetter {
    /// Watch image size
    fileprivate func observe_image_size(size_changed: @escaping (CGSize) -> Void) -> Self {
        let modifier = AnyImageModifier { image -> KFCrossPlatformImage in
            let image_size = image.size
            DispatchQueue.main.async { [size_changed, image_size] in
                size_changed(image_size)
            }
            return image
        }
        options.imageModifier = modifier
        return self
    }
}


public struct ImageFill {
    let filling: Bool?
    let height: CGFloat
        
    static func calculate_image_fill(geo_size: CGSize, img_size: CGSize, maxHeight: CGFloat, fillHeight: CGFloat) -> ImageFill {
        let shape = ImageShape.determine_image_shape(img_size)

        let xfactor = geo_size.width / img_size.width
        let scaled = img_size.height * xfactor
        
        //print("calc_img_fill \(img_size.width)x\(img_size.height) xfactor:\(xfactor) scaled:\(scaled)")
        
        // calculate scaled image height
        // set scale factor and constrain images to minimum 150
        // and animations to scaled factor for dynamic size adjustment
        switch shape {
        case .portrait, .landscape:
            let filling = scaled > maxHeight
            let height = filling ? fillHeight : scaled
            return ImageFill(filling: filling, height: height)
        case .square, .unknown:
            return ImageFill(filling: nil, height: scaled)
        }
    }
}

// MARK: - Preview Provider
struct ImageCarousel_Previews: PreviewProvider {
    static var previews: some View {
        let url: MediaUrl = .image(URL(string: "https://jb55.com/red-me.jpg")!)
        let test_video_url: MediaUrl = .video(URL(string: "http://cdn.jb55.com/s/zaps-build.mp4")!)
        ImageCarousel<AnyView>(state: test_damus_state, evid: test_note.id, urls: [test_video_url, url])
            .environmentObject(OrientationTracker())
    }
}

