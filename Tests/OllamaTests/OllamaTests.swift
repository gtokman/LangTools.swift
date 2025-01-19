import XCTest
import LangTools
@testable import TestUtils
@testable import Ollama

class OllamaTests: XCTestCase {
    var api: Ollama!
    
    override func setUp() {
        super.setUp()
        URLProtocol.registerClass(MockURLProtocol.self)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        api = Ollama(baseURL: URL(string: "http://localhost:11434")!).configure(testURLSessionConfiguration: config)
    }
    
    override func tearDown() {
        MockURLProtocol.mockNetworkHandlers.removeAll()
        URLProtocol.unregisterClass(MockURLProtocol.self)
        super.tearDown()
    }
    
    func testListModels() async throws {
        MockURLProtocol.mockNetworkHandlers[Ollama.ListModelsRequest.endpoint] = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            return (.success(try self.getData(filename: "list_models_response-ollama")!), 200)
        }
        
        let response = try await api.listModels()
        XCTAssertEqual(response.models.count, 2)
        
        let firstModel = response.models[0]
        XCTAssertEqual(firstModel.name, "codellama:13b")
        XCTAssertEqual(firstModel.size, 7365960935)
        XCTAssertEqual(firstModel.details.family, "llama")
        XCTAssertEqual(firstModel.details.parameterSize, "13B")
        XCTAssertEqual(firstModel.details.quantizationLevel, "Q4_0")
        
        let secondModel = response.models[1]
        XCTAssertEqual(secondModel.name, "llama3:latest")
        XCTAssertEqual(secondModel.size, 3825819519)
        XCTAssertEqual(secondModel.details.family, "llama")
        XCTAssertEqual(secondModel.details.parameterSize, "7B")
    }
    
    func testListModelsError() async throws {
        MockURLProtocol.mockNetworkHandlers[Ollama.ListModelsRequest.endpoint] = { _ in
            return (.success(try self.getData(filename: "error")!), 404)
        }
        
        do {
            _ = try await api.listModels()
            XCTFail("Expected error to be thrown")
        } catch let error as LangToolError {
            if case .responseUnsuccessful(let statusCode, _) = error {
                XCTAssertEqual(statusCode, 404)
            } else {
                XCTFail("Unexpected error type")
            }
        }
    }

    func testListRunningModels() async throws {
        MockURLProtocol.mockNetworkHandlers[Ollama.ListRunningModelsRequest.endpoint] = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            return (.success(try self.getData(filename: "list_running_models_response")!), 200)
        }

        let response = try await api.listRunningModels()
        XCTAssertEqual(response.models.count, 1)

        let model = response.models[0]
        XCTAssertEqual(model.name, "mistral:latest")
        XCTAssertEqual(model.size, 5137025024)
        XCTAssertEqual(model.details.family, "llama")
        XCTAssertEqual(model.details.parameterSize, "7.2B")
        XCTAssertEqual(model.details.quantizationLevel, "Q4_0")
        XCTAssertEqual(model.sizeVRAM, 5137025024)
    }

    func testShowModel() async throws {
        MockURLProtocol.mockNetworkHandlers[Ollama.ShowModelRequest.endpoint] = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            return (.success(try self.getData(filename: "show_model_response")!), 200)
        }

        let response = try await api.showModel("mistral:latest")
        XCTAssertFalse(response.modelfile.isEmpty)
        XCTAssertEqual(response.parameters, "num_ctx 4096")
        XCTAssertEqual(response.details.family, "llama")
        XCTAssertEqual(response.details.parameterSize, "7B")
        XCTAssertEqual(response.details.quantizationLevel, "Q4_0")
        XCTAssertEqual(response.modelInfo["architecture"]?.string, "llama")
        XCTAssertEqual(response.modelInfo["vocab_size"]?.integer, 32000)
    }

    func testDeleteModel() async throws {
        MockURLProtocol.mockNetworkHandlers[Ollama.DeleteModelRequest.endpoint] = { request in
            XCTAssertEqual(request.httpMethod, "DELETE")
            return (.success(try self.getData(filename: "success_response")!), 200)
        }

        let response = try await api.deleteModel("mistral:latest")
        XCTAssertEqual(response.status, "success")
    }

    func testCopyModel() async throws {
        MockURLProtocol.mockNetworkHandlers[Ollama.CopyModelRequest.endpoint] = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            return (.success(try self.getData(filename: "success_response")!), 200)
        }

        let response = try await api.copyModel(source: "llama2", destination: "llama2-backup")
        XCTAssertEqual(response.status, "success")
    }


    func testPullModel() async throws {
        MockURLProtocol.mockNetworkHandlers[Ollama.PullModelRequest.endpoint] = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            return (.success(try self.getData(filename: "pull_model_response")!), 200)
        }

        let response = try await api.pullModel("llama2")
        XCTAssertEqual(response.status, "downloading model")
        XCTAssertEqual(response.total, 5137025024)
        XCTAssertEqual(response.completed, 2568512512)
    }

    func testStreamPullModel() async throws {
        MockURLProtocol.mockNetworkHandlers[Ollama.PullModelRequest.endpoint] = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            // XCTAssertTrue(try JSONDecoder().decode(Ollama.PullModelRequest.self, from: request.httpBody!).stream ?? false)
            return (.success(try self.getData(filename: "pull_model_stream_response", fileExtension: "txt")!), 200)
        }
        
        var results: [Ollama.PullModelResponse] = []
        for try await response in api.streamPullModel("llama2") {
            results.append(response)
        }
        
        XCTAssertEqual(results.count, 8)
        
        // Check manifest phase
        XCTAssertEqual(results[0].status, "pulling manifest")
        
        // Check initial download phase
        XCTAssertEqual(results[1].status, "downloading sha256:2ae6f6dd7a3dd734790bbbf58b8909a606e0e7e97e94b7604e0aa7ae4490e6d8")
        XCTAssertEqual(results[1].total, 2142590208)
        XCTAssertNil(results[1].completed)
        
        // Check download progress
        XCTAssertEqual(results[2].status, "downloading sha256:2ae6f6dd7a3dd734790bbbf58b8909a606e0e7e97e94b7604e0aa7ae4490e6d8")
        XCTAssertEqual(results[2].total, 2142590208)
        XCTAssertEqual(results[2].completed, 241970)
        
        // Check final download progress
        XCTAssertEqual(results[3].status, "downloading sha256:2ae6f6dd7a3dd734790bbbf58b8909a606e0e7e97e94b7604e0aa7ae4490e6d8")
        XCTAssertEqual(results[3].total, 2142590208)
        XCTAssertEqual(results[3].completed, 1071295104)
        
        // Check final phases
        XCTAssertEqual(results[4].status, "verifying sha256 digest")
        XCTAssertEqual(results[5].status, "writing manifest")
        XCTAssertEqual(results[6].status, "removing any unused layers")
        XCTAssertEqual(results[7].status, "success")
    }

    func testPushModel() async throws {
        MockURLProtocol.mockNetworkHandlers[Ollama.PushModelRequest.endpoint] = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            return (.success(try self.getData(filename: "push_model_response")!), 200)
        }

        let response = try await api.pushModel("namespace/llama2:latest")
        XCTAssertEqual(response.status, "pushing model")
        XCTAssertEqual(response.total, 1928429856)
    }

    func testStreamPushModel() async throws {
        MockURLProtocol.mockNetworkHandlers[Ollama.PushModelRequest.endpoint] = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            // XCTAssertTrue(try JSONDecoder().decode(Ollama.PushModelRequest.self, from: request.httpBody!).stream ?? false)
            return (.success(try self.getData(filename: "push_model_stream_response", fileExtension: "txt")!), 200)
        }
        
        var results: [Ollama.PushModelResponse] = []
        for try await response in api.streamPushModel("mattw/pygmalion:latest") {
            results.append(response)
        }
        
        XCTAssertEqual(results.count, 6)
        
        // Check initial phase
        XCTAssertEqual(results[0].status, "retrieving manifest")
        
        // Check upload start
        XCTAssertEqual(results[1].status, "starting upload")
        XCTAssertEqual(results[1].digest, "sha256:bc07c81de745696fdf5afca05e065818a8149fb0c77266fb584d9b2cba3711ab")
        XCTAssertEqual(results[1].total, 1928429856)
        
        // Check upload progress
        XCTAssertEqual(results[2].status, "uploading")
        
        // Check final upload progress
        XCTAssertEqual(results[3].status, "uploading")
        
        // Check final phases
        XCTAssertEqual(results[4].status, "pushing manifest")
        XCTAssertEqual(results[5].status, "success")
    }

    func testCreateModel() async throws {
        MockURLProtocol.mockNetworkHandlers[Ollama.CreateModelRequest.endpoint] = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            return (.success(try self.getData(filename: "success_response")!), 200)
        }

        let response = try await api.createModel(model: "custom-model", modelfile: "FROM llama2\nSYSTEM You are a helpful assistant.")
        XCTAssertEqual(response.status, "success")
    }
}
