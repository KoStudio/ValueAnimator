//
// Created by brownsoo han on 2018. 3. 12..
//

import Foundation

public class ValueAnimator: Hashable {

    public struct Option {
        let yoyo: Bool
        let repeatCount: Int
        let delay: TimeInterval
    }

    public class OptionBuilder {
        var yoyo: Bool = false
        var repeatCount: Int = 0
        var delay: TimeInterval = 0

        public init() {
        }

        public func setYoyo(_ v: Bool) -> OptionBuilder {
            yoyo = v
            return self
        }

        public func setRepeatCount(_ v: Int) -> OptionBuilder {
            repeatCount = v
            return self
        }

        public func setDelay(_ v: TimeInterval) -> OptionBuilder {
            delay = v
            return self
        }

        public func build() -> Option {
            return Option(yoyo: yoyo, repeatCount: repeatCount, delay: delay)
        }
    }

    public typealias EndFunction = () -> Void
    public typealias ChangeFunction = (String, Double) -> Void

    private lazy var objectIdentifier = ObjectIdentifier(self)
    private var props = [String]()
    private var startTime: TimeInterval = 0
    private var initials = [String: Double]()
    private var changes = [String: Double]()
    private var duration: TimeInterval = 1
    private var easing: Easing!

    /// seconds in covered on timeline
    private var covered: TimeInterval = 0
    /// seconds to delay
    private var delay: TimeInterval = 0
    /// yoyo animation
    public private(set) var yoyo = false
    /// how many it repeat animation.
    public private(set) var repeatCount: Int = 0
    /// animated count
    public private(set) var counted: Int = 0
    public private(set) var isAnimating = false
    public private(set) var isFinished = false
    public private(set) var isDisposed = false

    /// callback for animation updates
    public var changeFunction: ChangeFunction? = nil
    /// callback for animation finishes
    public var endFunction: EndFunction? = nil

    public var hashValue: Int {
        return self.objectIdentifier.hashValue
    }

    public static func ==(left: ValueAnimator, right: ValueAnimator) -> Bool {
        return left.objectIdentifier == right.objectIdentifier
    }

    private init() {
    }

    public func resume() {
        isAnimating = true
    }

    public func pause() {
        isAnimating = false
    }

    public func finish() {
        isFinished = true
    }

    public func dispose() {
        isDisposed = true
    }


    // MARK: class values

    static public var debug = false
    static public var frameRate: Int = 50 {
        didSet {
            sleepTime = 1 / Double(frameRate)
        }
    }
    static private var nowTime: TimeInterval = 0
    static private var renderer: Thread? = nil
    static private var aniList = Set<ValueAnimator>()
    static private var sleepTime: TimeInterval = 0.02

    static public func finishAll() {
        aniList.forEach {
            $0.finish()
        }
    }

    static public func disposeAll() {
        aniList.removeAll()
    }

    static public func of(_ prop: String,
                          from: Double,
                          to: Double,
                          duration: TimeInterval,
                          changeFunction: ChangeFunction? = nil) -> ValueAnimator {
        return animate(props: [prop], from: [from], to: [to], duration: duration,
            onChanged: changeFunction, easing: EaseSine.easeOut())
    }

    static public func animate(prop: String,
                               from: Double,
                               to: Double,
                               duration: TimeInterval,
                               onChanged: ChangeFunction? = nil,
                               easing: Easing? = nil,
                               option: Option? = nil) -> ValueAnimator {
        return animate(props: [prop], from: [from], to: [to], duration: duration,
            onChanged: onChanged, easing: easing, option: option)
    }

    static public func animate(props: [String],
                               from: [Double],
                               to: [Double],
                               duration: TimeInterval,
                               onChanged: ChangeFunction? = nil,
                               easing: Easing? = nil,
                               option: Option? = nil,
                               endFunction: EndFunction? = nil) -> ValueAnimator {
        let ani = ValueAnimator()
        ani.props = props
        for (i, p) in props.enumerated() {
            ani.initials[p] = from[i]
            ani.changes[p] = to[i] - from[i]
        }
        ani.duration = duration
        ani.easing = easing ?? EaseLinear.easeNone()
        ani.endFunction = endFunction
        if let option = option {
            ani.yoyo = option.yoyo
            ani.repeatCount = option.repeatCount
            ani.delay = option.delay
        }
        if ani.yoyo && ani.repeatCount > 0 {
            ani.repeatCount *= 2
        }
        ani.changeFunction = onChanged
        ani.startTime = Date().timeIntervalSince1970


        aniList.insert(ani)
        if debug {
            print("ValueAnimator -----------: aniList added id: \(ani.hashValue)")
            if let render = renderer {
                print("render.isFinished -----------: \(render.isFinished)")
            }
        }
        // start runLoop if not running
        if renderer == nil || renderer?.isFinished == true {
            renderer = Thread(target: self, selector: #selector(onProgress), object: nil)
            renderer?.name = "renderer"
            renderer?.qualityOfService = .default
            renderer?.start()
        }

        return ani
    }

    @objc
    static private func onProgress() {
        while aniList.count > 0 {
            for ani in aniList {
                update(ani)
            }
            Thread.sleep(forTimeInterval: sleepTime)
            if Thread.main.isFinished {
                print("ValueAnimator is finished because main thread is finished")
                Thread.exit()
            }
        }
        if debug {
            print("ValueAnimator nothing to animate")
        }
        Thread.exit()
    }

    static private func update(_ ani: ValueAnimator) {
        if ani.isDisposed {
            dispose(ani)
            return
        }
        if ani.isFinished {
            finish(ani)
            return
        }
        nowTime = Date().timeIntervalSince1970
        if !ani.isAnimating {
            ani.startTime = nowTime - ani.covered * 1000.0
            return
        }
        if ani.delay > 0 {
            ani.delay -= (nowTime - ani.startTime)
            ani.startTime = nowTime
            return
        }
        // 시간 계산
        ani.covered = nowTime - ani.startTime
        // repeating
        if ani.covered >= ani.duration {
            if ani.yoyo {
                if ani.repeatCount <= 0 || ani.repeatCount > ani.counted {
                    for p in ani.props {
                        if let initial = ani.initials[p],
                           let change = ani.changes[p] {
                            let changed = initial + change
                            ani.changeFunction?(p, changed)
                            ani.initials[p] = changed
                            ani.changes[p]! *= -1
                        }
                    }
                    ani.startTime = nowTime
                    ani.counted += 1
                    return
                }
            }
            if ani.counted < ani.repeatCount {
                for p in ani.props {
                    if let initial = ani.initials[p] {
                        ani.changeFunction?(p, initial)
                    }
                }
                ani.startTime = nowTime
                ani.counted += 1
                return
            }

            finish(ani)
        } else {
            // call updates in progress
            for p in ani.props {
                ani.changeFunction?(p, ani.easing(ani.covered, ani.initials[p]!, ani.changes[p]!, ani.duration))
            }
        }
    }


    /// finish animation and update value with target
    static private func finish(_ ani: ValueAnimator) {
        aniList.remove(ani)
        for p in ani.props {
            if let initial = ani.initials[p],
               let change = ani.changes[p] {
                ani.changeFunction?(p, initial + change)
            }
        }
        ani.isFinished = true
        ani.endFunction?()
    }

    /// finish animation during animation
    static private func dispose(_ ani: ValueAnimator) {
        aniList.remove(ani)
        ani.isFinished = true
    }
}
