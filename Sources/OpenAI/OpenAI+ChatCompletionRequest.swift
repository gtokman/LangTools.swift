//
//  OpenAI+ChatCompletionRequest.swift
//  openai-swift
//
//  Created by Reid Chatham on 12/7/23.
//

import Foundation
import LangTools


public extension OpenAI {
    func performChatCompletionRequest(messages: [Message], model: Model = .gpt35Turbo, stream: Bool = false, completion: @escaping (Result<OpenAI.ChatCompletionResponse, Error>) -> Void, didCompleteStreaming: ((Error?) -> Void)? = nil) {
        perform(request: OpenAI.ChatCompletionRequest(model: model, messages: messages, stream: stream), completion: completion, didCompleteStreaming: didCompleteStreaming)
    }
}

extension OpenAI {
    public struct ChatCompletionRequest: Codable, LangToolsChatRequest, LangToolsStreamableChatRequest, LangToolsCompletableChatRequest, LangToolsToolCallingChatRequest, LangToolsMultipleChoiceChatRequest {

        public typealias Response = ChatCompletionResponse
        public static var path: String { "chat/completions" }
        public static var url: URL { OpenAI.url.appending(path: path) }
        public let model: Model
        public var messages: [Message]
        public let temperature: Double?
        public let top_p: Double?
        public let n: Int? // how many chat completions to generate for each request
        public var stream: Bool?
        public let stream_options: StreamOptions?
        public let stop: Stop?
        public let max_tokens: Int?
        public let presence_penalty: Double?
        public let frequency_penalty: Double?
        public let logit_bias: [String: Double]?
        public let logprobs: Bool?
        public let top_logprobs: Int?
        public let user: String?
        public let response_format: ResponseFormat?
        public let seed: Int?
        public let tools: [Tool]?
        public let tool_choice: ToolChoice?
        public let parallel_tool_calls: Bool?

        @CodableIgnored
        var choose: (([Response.Choice]) -> Int)?

        public init(model: Model, messages: [Message], temperature: Double? = nil, top_p: Double? = nil, n: Int? = nil, stream: Bool? = nil, stream_options: StreamOptions? = nil, stop: Stop? = nil, max_tokens: Int? = nil, presence_penalty: Double? = nil, frequency_penalty: Double? = nil, logit_bias: [String: Double]? = nil, logprobs: Bool? = nil, top_logprobs: Int? = nil, user: String? = nil, response_type: ResponseType? = nil, seed: Int? = nil, tools: [Tool]? = nil, tool_choice: ToolChoice? = nil, parallel_tool_calls: Bool? = nil, choose: @escaping ([Response.Choice]) -> Int = {_ in 0}) {
            self.model = model
            self.messages = messages
            self.temperature = temperature
            self.top_p = top_p
            self.n = n
            self.stream = stream
            self.stream_options = stream_options
            self.stop = stop
            self.max_tokens = max_tokens
            self.presence_penalty = presence_penalty
            self.frequency_penalty = frequency_penalty
            self.logit_bias = logit_bias
            self.logprobs = logprobs
            self.top_logprobs = top_logprobs
            self.user = user
            self.response_format = response_type.flatMap { ResponseFormat(type: $0) }
            self.seed = seed
            self.tools = tools
            self.tool_choice = tool_choice
            self.parallel_tool_calls = parallel_tool_calls
            self.choose = choose
        }

        public struct StreamOptions: Codable {
            let include_usage: Bool
        }

        public enum ToolChoice: Codable {
            case none, auto, required
            case tool(ToolWrapper)

            public enum ToolWrapper: Codable {
                case function(String)

                public struct FunctionDetails: Codable {
                    var name: String
                    public init(name: String) { self.name = name }
                }

                enum CodingKeys: String, CodingKey {
                    case type, function
                }

                public init(from decoder: Decoder) throws {
                    let container = try decoder.container(keyedBy: CodingKeys.self)
                    let type = try container.decode(String.self, forKey: .type)
                    switch type {
                    case "function":
                        let functionDetails = try container.decode(FunctionDetails.self, forKey: .function)
                        self = .function(functionDetails.name)
                    default: throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Invalid type value")
                    }
                }

                public func encode(to encoder: Encoder) throws {
                    var container = encoder.container(keyedBy: CodingKeys.self)
                    switch self {
                    case .function(let name):
                        try container.encode("function", forKey: .type)
                        try container.encode(FunctionDetails(name: name), forKey: .function)
                    }
                }
            }

            public init(from decoder: Decoder) throws {
                let container = try decoder.singleValueContainer()
                if let stringValue = try? container.decode(String.self) {
                    switch stringValue {
                    case "none": self = .none
                    case "auto": self = .auto
                    case "required": self = .required
                    default: throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid value for ToolChoice: \(stringValue)")
                    }
                } else { self = .tool(try ToolWrapper(from: decoder)) }
            }

            public func encode(to encoder: Encoder) throws {
                var container = encoder.singleValueContainer()
                switch self {
                case .none: try container.encode("none")
                case .auto: try container.encode("auto")
                case .required: try container.encode("required")
                case .tool(let toolWrapper): try container.encode(toolWrapper)
                }
            }
        }

        public enum Stop: Codable {
            case string(String)
            case array([String])

            public init(from decoder: Decoder) throws {
                let container = try decoder.singleValueContainer()
                if let string = try? container.decode(String.self) { self = .string(string) }
                else if let array = try? container.decode([String].self) { self = .array(array) }
                else { throw DecodingError.typeMismatch(Stop.self, DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Invalid type for Stop")) }
            }

            public func encode(to encoder: Encoder) throws {
                var container = encoder.singleValueContainer()
                switch self {
                case .string(let string): try container.encode(string)
                case .array(let array): try container.encode(array)
                }
            }
        }

        public struct ResponseFormat: Codable {
            let type: ResponseType
            public init(type: ResponseType) {
                self.type = type
            }
        }

        public enum ResponseType: String, Codable {
            case text, json_object
        }
    }

    public struct ChatCompletionResponse: Codable, LangToolsStreamableChatResponse, LangToolsMultipleChoiceChatResponse, LangToolsToolCallingChatResponse {
        public typealias Delta = OpenAI.Message.Delta
        public typealias Message = OpenAI.Message
        public typealias ToolSelection = Message.ToolCall

        public var delta: OpenAI.Message.Delta? { choices[choose?(choices) ?? 0].delta }
        public var message: OpenAI.Message? { choices[choose?(choices) ?? 0].message }

        public let id: String
        public let object: String // chat.completion or chat.completion.chunk
        public let created: Int
        public let model: String? // TODO: make response return typed model response
        public let system_fingerprint: String?
        public var choices: [Choice]
        public let usage: Usage?

        @CodableIgnored
        var choose: (([Choice]) -> Int)?

        public init(id: String, object: String, created: Int, model: String?, system_fingerprint: String?, choices: [Choice], usage: Usage?) {
            self.id = id
            self.object = object
            self.created = created
            self.model = model
            self.system_fingerprint = system_fingerprint
            self.choices = choices
            self.usage = usage
        }

        public struct Choice: Codable, LangToolsMultipleChoiceChoice {
            public let index: Int
            public let message: Message?
            public let finish_reason: FinishReason?
            public let delta: Message.Delta?

            public init(index: Int, message: Message?, finish_reason: FinishReason?, delta: Message.Delta?) {
                self.index = index
                self.message = message
                self.finish_reason = finish_reason
                self.delta = delta
            }

            public enum FinishReason: String, Codable {//, LangToolsFinishReason {
                case stop, length, content_filter, tool_calls
            }

            func combining(with next: Choice) -> Choice {
                // We want to merge all `delta`s into the `message` parameter, however the first
                // ChatCompletionResponse we decode does not have a value for `message` if it is streaming
                // so we need to first merge the initial `delta` then merge the `next.delta`. We no longer
                // need the delta object but we preserve it to maintain api consistency with OpenAI.
                let message = combining(message ?? combining(nil, with: delta), with: next.delta)
                return Choice(index: index, message: message, finish_reason: finish_reason ?? next.finish_reason, delta: combining(delta, with: next.delta))
            }

            func combining(_ message: Message?, with delta: Message.Delta?) -> Message? {
                guard let delta = delta else { return message }
                return try! Message(role: message?.role ?? delta.role ?? .assistant, content: .string(message?.content.string ?? "" + (delta.content ?? "")), name: message?.name, tool_calls: combining(message?.tool_calls, with: delta.tool_calls))
            }

            func combining(_ delta: Message.Delta?, with next: Message.Delta?) -> Message.Delta? {
                guard let delta = delta, let next = next else { return delta ?? next }
                return Message.Delta(role: delta.role ?? next.role, content: delta.content ?? "" + (next.content ?? ""), tool_calls: combining(delta.tool_calls, with: next.tool_calls))
            }

            func combining(_ toolCalls: [Message.ToolCall]?, with next: [Message.ToolCall]?) -> [Message.ToolCall]? {
                guard let toolCalls = toolCalls, let next = next else { return toolCalls ?? next }
                return next.sorted().reduce(into: toolCalls.sorted()) { partialResult, next in
                    if (next.index ?? .max < partialResult.count) {
                        partialResult[next.index!] = combining(partialResult[next.index!], with: next)
                    } else {
                        partialResult.append(next)
                    }
                }
            }

            func combining(_ toolCall: Message.ToolCall, with next: Message.ToolCall) -> Message.ToolCall {
                return Message.ToolCall(index: next.index ?? toolCall.index ?? 0, id:  next.id ?? toolCall.id ?? "", type: toolCall.type ?? next.type ?? .function, function: combining(toolCall.function, with: next.function))
            }

            func combining(_ function: Message.ToolCall.Function, with next: Message.ToolCall.Function) -> Message.ToolCall.Function {
                return Message.ToolCall.Function(name: next.name ?? function.name ?? "", arguments: function.arguments + next.arguments)
            }
        }

        public struct Usage: Codable {
            public let prompt_tokens: Int
            public let completion_tokens: Int
            public let total_tokens: Int

            public init(prompt_tokens: Int, completion_tokens: Int, total_tokens: Int) {
                self.prompt_tokens = prompt_tokens
                self.completion_tokens = completion_tokens
                self.total_tokens = total_tokens
            }
        }

        public func combining(with next: ChatCompletionResponse) -> ChatCompletionResponse {
            return ChatCompletionResponse(id: next.id, object: next.object, created: next.created, model: next.model, system_fingerprint: next.system_fingerprint, choices: combining(choices, with: next.choices), usage: next.usage)
        }

        func combining(_ choices: [Choice], with next: [Choice]) -> [Choice] {
            if choices.isEmpty { return next }
            return zip(choices.sorted(), next.sorted()).map { $0.combining(with: $1) }
        }

        public static var empty: ChatCompletionResponse { ChatCompletionResponse(id: "", object: "", created: -1, model: nil, system_fingerprint: nil, choices: [], usage: nil) }
    }

    public enum ChatCompletionError: Error {
        case failedToDecodeFunctionArguments
        case missingRequiredFunctionArguments
    }
}

extension Array where Element == OpenAI.ChatCompletionResponse.Choice {
    func sorted() -> [Element] {
        return self.sorted(by: { $0.index < $1.index })
    }
}

extension Array where Element == OpenAI.Message.ToolCall {
    func sorted() -> [Element] {
        guard first?.index != nil else { return self }
        return self.sorted(by: { $0.index! < $1.index! }) // assume that if an index exists it exists for all tool calls
    }
}

@propertyWrapper
struct CodableIgnored<T>: Codable {
    var wrappedValue: T?
    init(wrappedValue: T?) { self.wrappedValue = wrappedValue }
    init(from decoder: Decoder) throws { self.wrappedValue = nil }
    func encode(to encoder: Encoder) throws {} // Do nothing
}

extension KeyedDecodingContainer {
    func decode<T>(_ type: CodableIgnored<T>.Type, forKey key: Self.Key) throws -> CodableIgnored<T> { return CodableIgnored(wrappedValue: nil) }
}

extension KeyedEncodingContainer {
    mutating func encode<T>(_ value: CodableIgnored<T>, forKey key: KeyedEncodingContainer<K>.Key) throws {} // Do nothing
}
