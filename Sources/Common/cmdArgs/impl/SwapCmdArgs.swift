public struct SwapCmdArgs: CmdArgs {
    /*conforms*/ public var commonState: CmdArgsCommonState
    public init(rawArgs: StrArrSlice) { self.commonState = .init(rawArgs) }
    public static let parser: CmdParser<Self> = .init(
        kind: .swap,
        help: swap_help_generated,
        flags: [
            "--swap-focus": trueBoolFlag(\.swapFocus),
            "--wrap-around": trueBoolFlag(\.wrapAround),
            "--move-mouse": trueBoolFlag(\.moveMouse),
            "--window-id": windowIdSubArgParser(),
        ],
        posArgs: [newMandatoryPosArgParser(\.target, parseCardinalOrDfsDirection, placeholder: CardinalOrDfsDirection.unionLiteral)],
    )

    public var target: Lateinit<CardinalOrDfsDirection> = .uninitialized
    public var swapFocus: Bool = false
    public var wrapAround: Bool = false
    public var moveMouse: Bool = false
}

func parseSwapCmdArgs(_ args: StrArrSlice) -> ParsedCmd<SwapCmdArgs> {
    return parseSpecificCmdArgs(SwapCmdArgs(rawArgs: args), args)
}
