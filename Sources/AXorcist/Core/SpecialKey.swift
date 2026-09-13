import CoreGraphics

// MARK: - Special Keys

// swiftlint:disable identifier_name
public enum SpecialKey: String {
    case escape
    case tab
    case space
    case delete
    case forwardDelete = "forwarddelete"
    case `return`
    case enter
    case up
    case down
    case left
    case right
    case pageUp = "pageup"
    case pageDown = "pagedown"
    case home
    case end
    case f1
    case f2
    case f3
    case f4
    case f5
    case f6
    case f7
    case f8
    case f9
    case f10
    case f11
    case f12

    // Single character keys
    case a
    case b
    case c
    case d
    case e
    case f
    case g
    case h
    case i
    case j
    case k
    case l
    case m
    case n
    case o
    case p
    case q
    case r
    case s
    case t
    case u
    case v
    case w
    case x
    case y
    case z

    // Digit keys
    case zero = "0"
    case one = "1"
    case two = "2"
    case three = "3"
    case four = "4"
    case five = "5"
    case six = "6"
    case seven = "7"
    case eight = "8"
    case nine = "9"

    init?(character: Character) {
        if let special = SpecialKey(rawValue: String(character).lowercased()) {
            self = special
        } else {
            return nil
        }
    }

    var keyCode: CGKeyCode? {
        switch self {
        case .escape: 53
        case .tab: 48
        case .space: 49
        case .delete: 51
        case .forwardDelete: 117
        case .return, .enter: 36
        case .up: 126
        case .down: 125
        case .left: 123
        case .right: 124
        case .pageUp: 116
        case .pageDown: 121
        case .home: 115
        case .end: 119
        case .f1: 122
        case .f2: 120
        case .f3: 99
        case .f4: 118
        case .f5: 96
        case .f6: 97
        case .f7: 98
        case .f8: 100
        case .f9: 101
        case .f10: 109
        case .f11: 103
        case .f12: 111
        case .a: 0
        case .b: 11
        case .c: 8
        case .d: 2
        case .e: 14
        case .f: 3
        case .g: 5
        case .h: 4
        case .i: 34
        case .j: 38
        case .k: 40
        case .l: 37
        case .m: 46
        case .n: 45
        case .o: 31
        case .p: 35
        case .q: 12
        case .r: 15
        case .s: 1
        case .t: 17
        case .u: 32
        case .v: 9
        case .w: 13
        case .x: 7
        case .y: 16
        case .z: 6
        case .zero: 29
        case .one: 18
        case .two: 19
        case .three: 20
        case .four: 21
        case .five: 23
        case .six: 22
        case .seven: 26
        case .eight: 28
        case .nine: 25
        }
    }
}

// swiftlint:enable identifier_name
