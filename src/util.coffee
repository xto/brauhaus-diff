###
Utility functions
###
diffutil =
    # Get the keys found only in left, only in right, and both objects. Ignores
    # values that are functions and keys that are private (start with '_').
    getKeys: (left, right) ->
        leftOnly = []
        both = []

        for key, val of left when diffutil.keyPass key, val
            if key of right and diffutil.keyPass key, right[key]
                both.push key
            else
                leftOnly.push key

        rightOnly = []
        for key, val of right when diffutil.keyPass key, val
            if key not of left or not diffutil.keyPass key, left[key]
                rightOnly.push key

        [leftOnly, rightOnly, both]

    # Test whether a key is valid for the purposes of performing a diff.
    keyPass: (key, val) ->
        if typeof val is 'function' or key.charAt(0) is '_'
            false
        else
            true

    # Check if an object or array is empty
    isEmpty: (obj) ->
        if not obj?
            true
        if obj instanceof Array
            obj.length is 0
        else
            for key, val of obj when diffutil.keyPass key, val
                return false
            true

    # Check if all objects are of a given type
    areAll: (type, args...) ->
        for arg in args
            return false if arg not instanceof type
        if args.length > 0 then true else false

    # Check if any of the object are of a given type. Note this function takes
    # different input than areAll!
    areAny: (type, args) ->
        for arg in args
            return true if arg instanceof type
        false

    # Check if two objects are considered compatible types. This will be true if
    # they share the same prototype or have >75% of the same keys.
    compatibleTypes: (left, right) ->
        if (left instanceof Array) != (right instanceof Array)
            false
        else if left instanceof right.constructor or right instanceof left.constructor
            true
        else
            [leftKeys, rightKeys, bothKeys] = diffutil.getKeys left, right
            return bothKeys.length > 0.75 * (leftKeys.length + rightKeys.length + bothKeys.length)

    # Compute the hash for a given object.
    hash: (obj) ->
        if obj._diffKeys?
            hash = murmur()
            diffutil.hashObjKeys hash, obj, obj._diffKeys
        else
            hash = murmur(JSON.stringify obj)
        hash.result().toString(32)

    # Hash the keys (and associated values) for an object
    hashObjKeys: (hash, obj, keys) ->
        for val in keys
            if val instanceof Array
                diffutil.hashObjKeys hash, obj, val
            else
                hash.hash val
                hash.hash ':'
                hash.hash obj[val].toString()
                hash.hash '|'
        return

    # Get a shallow copy of the object containing just the keys that are used
    # for diffing.
    diffCopy: (obj, options) ->
        copy = if typeof obj.toJSON is 'function' then obj.toJSON() else diffutil.shallowCopy obj, true
        if copy instanceof Object
            delete copy[key] for key, val of copy when not diffutil.keyPass key, val
            if options.removeDefaultValues is true
                delete copy[key] for key of obj when not obj.hasOwnProperty key
        copy

    # Get a shallow copy of the object
    shallowCopy: (obj, ignoreType) ->
        if obj instanceof Array
            copy = obj.slice()
        else if obj instanceof Object and obj not instanceof Function
            if ignoreType
                copy = {}
                copy[key] = val for key, val of obj
            else
                copy = Object.create Object.getPrototypeOf obj
                copy[key] = val for own key, val of obj
        return copy ? obj

    # Check a key/val pair against another key/val pair
    checkKeyVal: (leftKey, leftVal, rightKey, rightVal) ->
        if diffutil.areAll Array, leftKey, rightKey
            diffutil.arrayCompare(leftKey, rightKey) and
            diffutil.arrayCompare(leftVal, rightVal)
        else
            leftKey is rightKey and leftVal is rightVal

    # Get the key and value for a given key level. Keys may be simple types or
    # arrays of simple types.
    getKeyVal: (obj, level) ->
        if obj._diffKeyVal? and obj._diffKeyVal[level]?
            return obj._diffKeyVal[level]

        if obj._diffKeys? and obj._diffKeys[level]?
            key = obj._diffKeys[level]
            val = diffutil.getValForKey obj, key
        else
            key = '_nokey'
        obj._diffKeyVal ?= []
        obj._diffKeyVal[level] = [key, val]

    # Get the value on object for the given key. If key is an array, an array
    # of values will be returned.
    getValForKey: (obj, key) ->
        if key instanceof Array
            val = diffutil.getValForKey(obj, k) for k in key
        else
            obj[key]

    # Compare arrays for equality
    arrayCompare: (left, right) ->
        if left is right
            return true
        if left.length isnt right.length
            return false
        for i in [0...left.length]
            if diffutil.areAll Array, left[i], right[i]
                return false if not diffutil.arrayCompare left[i], right[i]
            else
                return false if left[i] isnt right[i]
        return true

    # Get a "closeness" score for a set of keys and values. The higher the
    # score, the better
    getKeyValScore: (leftKey, leftVal, rightKey, rightVal, options) ->
        score = 0
        if diffutil.areAll Array, leftKey, rightKey
            for i in [0...leftKey.length]
                score += diffutil.getKeyValScore leftKey[i], leftVal[i],
                                                 rightKey[i], rightVal[i],
                                                 options, options.dontScoreKeys
        else if leftKey is rightKey
            score = 1 if not options.dontScoreKeys
            if leftVal is rightVal
                ++score
            else if options.fuzzyStrings and typeof leftVal is 'string' and typeof rightVal is 'string'
                # Multiply match percentage by 0.95 to ensure a perfect match's
                # score always beats a fuzzy match's score
                #  e.g. 2 vs (1 + 0.95 * fuzzyMatch)
                score += 0.95 * diffutil.fuzzyMatch leftVal, rightVal, options
        score

    # Get an array of "closeness" scores for two objects.
    getMatchScore: (left, right, options) ->
        scores = []
        start_level = options.start_level
        loop
            [leftKey, leftVal] = diffutil.getKeyVal left, start_level
            [rightKey, rightVal] = diffutil.getKeyVal right, start_level

            leftValid = leftKey isnt '_nokey'
            rightValid = rightKey isnt '_nokey'

            if leftValid and rightValid
                scores.push diffutil.getKeyValScore(leftKey, leftVal, rightKey, rightVal, options)
            else if not leftValid and not rightValid
                break
            else
                scores.push 0

            ++start_level

        scores.push(0) if scores.length is 0
        scores

    # Get the closeness of two strings as a percentage if the strings pass the
    # fuzzyStrings filter.
    fuzzyMatch: (left, right, options) ->
        # Check the cache before doing fuzzy matching
        if left.length < right.length
            shorter = left
            longer = right
        else
            shorter = right
            longer = left

        if options._fuzzyMatchCache?
            return options._fuzzyMatchCache[shorter][longer] if options._fuzzyMatchCache[shorter]?[longer]?
        else
            options._fuzzyMatchCache = {}
            options._fuzzySortCache = {}

        options._fuzzyMatchCache[shorter] ?= {}

        cutoff = options.fuzzyStrings left, right
        len = Math.max left.length, right.length
        lev = levenshtein.get(left, right) / len
        if lev <= cutoff
            options._fuzzyMatchCache[shorter][longer] = 1 - lev
        else if left.indexOf(' ') >= 0 and right.indexOf(' ') >= 0
            # Split the strings, sort, stringify, and then compare again
            left = if options._fuzzySortCache[left]?
                options._fuzzySortCache[left]
            else
                options._fuzzySortCache[left] = left.split(' ').filter((s) -> s != '').sort().join(' ')

            right = if options._fuzzySortCache[right]?
                options._fuzzySortCache[right]
            else
                options._fuzzySortCache[right] = right.split(' ').filter((s) -> s != '').sort().join(' ')

            lev = levenshtein.get(left, right) / len
            if lev <= cutoff
                options._fuzzyMatchCache[shorter][longer] = 1 - lev
            else
                options._fuzzyMatchCache[shorter][longer] = 0
        else
            options._fuzzyMatchCache[shorter][longer] = 0

    # Return the first value we can get from a category or the object itself
    getOne: (val) ->
        if val instanceof Category
            if val.obj instanceof Array
                diffutil.getOne val.obj[0]
            else
                val.obj
        else
            val

    # Valid directions to apply a diff.
    #  LeftToRight means the object is being transformed from a left object to a
    #              right object via the diff.
    #  RightToLeft means the opposite.
    Directions:
        LeftToRight: 1
        RightToLeft: 2

    # Get the direction constant for a given direction string
    getDirection: (direction) ->
        if not direction
            diffutil.Directions.LeftToRight
        else if typeof direction is 'number'
            direction
        else
            c = direction.charAt(0).toLowerCase()
            if c isnt 'f' and c isnt 'r' then diffutil.Directions.LeftToRight else diffutil.Directions.RightToLeft

    # Do a simple value compare. Objects always compare to each other as true.
    simpleCompare: (left, right) ->
        if diffutil.areAll Object, left, right
            true
        else if not left? and not right?
            true
        else
            left is right

###
Manages the failure state of a diff operation.
###
class FailState
    constructor: (fail) ->
        # We're already a FailState, so return ourselves
        if fail instanceof FailState
            return fail
        # We were called with `new`, so make it happen
        else if this instanceof FailState
            @fail = fail ? true
            @state = []
            @canFail = typeof @fail is 'function' or !!@fail
        # We were called without `new` but need to create a new instance
        else
            return new FailState fail

    # Add a key to the state
    push: (key) ->
        @state.push(key) if @canFail

    # Remove a key from the state
    pop: ->
        @state.pop() if @canFail

    # Check expected and actual for a match, throwing an exception if they
    # don't and fail is true.
    check: (expected, actual) ->
        if @canFail and not diffutil.simpleCompare expected, actual
            fail = typeof @fail is 'function'
            if (fail and @fail @state, expected, actual) or (not fail and !!@fail)
                statestr = if @state.length then @state.join('.') else 'none'
                e = new Error 'Diff encountered an inconsistency ' +
                    "(key: #{statestr}, expected: #{expected}, actual: #{actual})"
                e.keys = @state
                e.expected = expected
                e.actual = actual
                throw e


###
Converts an options object into an identifiable type with defaults from the
global options object. Although this is a class, it should not be called with
the `new` keyword. The constructor functions in a way to return a new instance
if needed or the current instance if possible.
###
class ConvertToOptions
    constructor: (options) ->
        # If the options object was already created, return it
        if options instanceof ConvertToOptions
            return options
        # We were called with `new`, so make it happen
        else if this instanceof ConvertToOptions
            if options?
                @[key] = val for own key, val of options
            ConvertToOptions.normalize this
        # We were called without `new` but need to create a new instance
        else
            return new ConvertToOptions options

    # Normalize the options to be the right types.
    @normalize = (options) ->
        # Coerce to booleans
        options.exportUtil = !!options.exportUtil if options.hasOwnProperty 'exportUtil'
        options.usingBrauhausStyles = !!options.usingBrauhausStyles if options.hasOwnProperty 'usingBrauhausStyles'
        options.removeDefaultValues = !!options.removeDefaultValues if options.hasOwnProperty 'removeDefaultValues'
        options.enablePostDiff = !!options.enablePostDiff if options.hasOwnProperty 'enablePostDiff'
        options.enablePostApply = !!options.enablePostApply if options.hasOwnProperty 'enablePostApply'

        # Determine how to handle fuzzy strings based on type
        if options.hasOwnProperty 'fuzzyStrings'
            if options.fuzzyStrings is true
                options.fuzzyStrings = defaultFuzzyStrings
            else if typeof options.fuzzyStrings is 'number'
                f = (n) -> return -> n
                options.fuzzyStrings = f options.fuzzyStrings
            else if typeof options.fuzzyStrings is 'function'
                options.fuzzyStrings = options.fuzzyStrings
            else
                options.fuzzyStrings = false
        options

# Set up the prototype so the default options are used for any unset options
ConvertToOptions.prototype = Options


diffutil.FailState = FailState
diffutil.ConvertToOptions = ConvertToOptions
