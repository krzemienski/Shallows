public protocol CacheDesign {
    
    var name: String { get }
    
}

public protocol CacheProtocol : ReadOnlyCacheProtocol, WritableCacheProtocol { }

public struct Cache<Key, Value> : CacheProtocol {
    
    public let name: String
    
    private let _retrieve: (Key, @escaping (Result<Value>) -> ()) -> ()
    private let _set: (Value, Key, @escaping (Result<Void>) -> ()) -> ()
    
    public init(name: String/* = "Unnamed cache \(Key.self) : \(Value.self)"*/,
                retrieve: @escaping (Key, @escaping (Result<Value>) -> ()) -> (),
                set: @escaping (Value, Key, @escaping (Result<Void>) -> ()) -> ()) {
        self._retrieve = retrieve
        self._set = set
        self.name = name
    }
    
    public init<CacheType : CacheProtocol>(_ cache: CacheType) where CacheType.Key == Key, CacheType.Value == Value {
        self._retrieve = cache.retrieve
        self._set = cache.set
        self.name = cache.name
    }
    
    public func retrieve(forKey key: Key, completion: @escaping (Result<Value>) -> ()) {
        _retrieve(key, completion)
    }
    
    public func set(_ value: Value, forKey key: Key, completion: @escaping (Result<Void>) -> () = { _ in }) {
        _set(value, key, completion)
    }
    
}

extension CacheProtocol {
    
    public func makeCache() -> Cache<Key, Value> {
        return Cache(self)
    }
    
    public func bothWayRetrieve<CacheType : ReadOnlyCacheProtocol>(forKey key: Key, backedBy cache: CacheType, completion: @escaping (Result<Value>) -> ()) where CacheType.Key == Key, CacheType.Value == Value {
        self.retrieve(forKey: key, completion: { (firstResult) in
            if firstResult.isFailure {
                shallows_print("Cache (\(self.name)) miss for key: \(key). Attempting to retrieve from \(cache.name)")
                cache.retrieve(forKey: key, completion: { (secondResult) in
                    if case .success(let value) = secondResult {
                        shallows_print("Success retrieving \(key) from \(cache.name). Setting value back to \(self.name)")
                        self.set(value, forKey: key, completion: { _ in completion(secondResult) })
                    } else {
                        shallows_print("Cache miss for final destination (\(cache.name)). Completing with failure result")
                        completion(secondResult)
                    }
                })
            } else {
                completion(firstResult)
            }
        })
    }
    
    public func set<CacheType : WritableCacheProtocol>(_ value: Value, forKey key: Key, pushingTo cache: CacheType, completion: @escaping (Result<Void>) -> ()) where CacheType.Key == Key, CacheType.Value == Value {
        self.set(value, forKey: key, completion: { (result) in
            if result.isFailure {
                shallows_print("Failed setting \(key) to \(self.name). Aborting")
                completion(result)
            } else {
                shallows_print("Succesfull set of \(key). Pushing to \(cache.name)")
                cache.set(value, forKey: key, completion: completion)
            }
        })
    }
    
    public func bothWayCombined<CacheType : CacheProtocol>(with cache: CacheType) -> Cache<Key, Value> where CacheType.Key == Key, CacheType.Value == Value {
        return Cache<Key, Value>(name: "\(self.name) <-> \(cache.name)", retrieve: { (key, completion) in
            self.bothWayRetrieve(forKey: key, backedBy: cache, completion: completion)
        }, set: { (value, key, completion) in
            self.set(value, forKey: key, pushingTo: cache, completion: completion)
        })
    }
    
    public func bothWayCombined<CacheType : ReadOnlyCacheProtocol>(with cache: CacheType) -> Cache<Key, Value> where CacheType.Key == Key, CacheType.Value == Value {
        return Cache<Key, Value>(name: "\(self.name) <- \(cache.name)", retrieve: { (key, completion) in
            self.bothWayRetrieve(forKey: key, backedBy: cache, completion: completion)
        }, set: { (value, key, completion) in
            self.set(value, forKey: key, completion: completion)
        })
    }
    
}