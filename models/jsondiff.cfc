component singleton {

    variables.uniqueKeyName = '________key';
    function numericCheck(value) {
        if (
            getMetadata(value).getName() == 'java.lang.Double' ||
            getMetadata(value).getName() == 'java.lang.Integer'
        )
            return true;
        return false
    }

    function isSame(first, second) {
        if (isNull(first) && isNull(second)) return true;
        if (isNull(first) || isNull(second)) return false;
        if (isSimpleValue(first) && isSimpleValue(second)) {
            if (numericCheck(first) && numericCheck(second) && precisionEvaluate(first - second) != 0) {
                return false;
            } else if (first != second) {
                return false;
            }
            return true;
        }

        // We know that first and second have the same type so we can just check the
        // first type from now on.1
        if (isArray(first) && isArray(second)) {
            // Short circuit if they're not the same length;
            if (first.len() != second.len()) {
                return false;
            }
            for (var i = 1; i <= first.len(); i++) {
                if (isSame(first[i], second[i]) == false) {
                    return false;
                }
            }
            return true;
        }

        if (isStruct(first) && isStruct(second)) {
            // echo('we are here')
            // An object is equal if it has the same key/value pairs.
            var keysSeen = {};
            for (var key in first) {
                // echo('first -> ' & key & '<br/>');
                if (structKeyExists(first, key) && structKeyExists(second, key)) {
                    if (isSame(first[key], second[key]) == false) {
                        return false;
                    }
                    keysSeen[key] = true;
                }
            }
            // Now check that there aren't any keys in second that weren't
            // in first.
            for (var key2 in second) {
                // echo('second -> ' & key2 &  '<br/>');
                if (!structKeyExists(second, key2) || !structKeyExists(keysSeen, key2)) {
                    return false;
                }
            }
            return true;
        }
        return false;
    }

    function groupData(required array data, required array uniqueKeys) {
        return data.reduce((acc, x) => {
            var uniqueKey = uniqueKeys.reduce((accKey, key) => {
                accKey.append(x[key]);
                return accKey;
            }, []);
            uniqueKey = serializeJSON(uniqueKey);
            x[variables.uniqueKeyName] = uniqueKey;
            acc[uniqueKey] = x;
            return acc
        }, {})
    }


    function diffByKey(
        array first = [],
        array second = [],
        required any uniqueKeys,
        array ignoreKeys = []
    ) {
        if (!isArray(uniqueKeys)) {
            uniqueKeys = [uniqueKeys];
        }
        var data1 = groupData(first, uniqueKeys);
        var data2 = groupData(second, uniqueKeys);
        var diffData = diff(data1, data2, ignoreKeys);
        var groupedDiff = diffData.reduce((acc, x) => {
            if (x.type == 'add') {
                key = x.new[variables.uniqueKeyName];
                x.new.delete(variables.uniqueKeyName)
                acc[x.type].append({'key': deserializeKey(key), 'data': x.new});
            } else if (x.type == 'remove') {
                key = x.old[variables.uniqueKeyName];
                x.old.delete(variables.uniqueKeyName)
                acc[x.type].append({'key': deserializeKey(key), 'data': x.old});
            } else if (x.type == 'change') {
                if (!acc[x.type].keyExists(x.path[1])) acc[x.type][x.path[1]] = [];
                var pathRest = arraySlice(x.path, 2);
                acc[x.type][x.path[1]].append({
                    'key': pathRest[1],
                    'path': pathRest,
                    'new': x.new,
                    'old': x.old
                });
            }
            return acc
        }, {'add': [], 'remove': [], 'change': {}});
        groupedDiff['update'] = groupedDiff.change.reduce((acc, key, value) => {
            data1[key].delete(variables.uniqueKeyName);
            data2[key].delete(variables.uniqueKeyName);
            acc.push({
                'key': deserializeKey(key),
                'orig': data1[key],
                'data': data2[key],
                'changes': value
            })
            return acc;
        }, []);
        groupedDiff.delete('change');
        first.map((row) => {
            row.delete(variables.uniqueKeyName)
        })
        second.map((row) => {
            row.delete(variables.uniqueKeyName)
        })
        return groupedDiff;
    }

    function deserializeKey(serializedKey) {
        var valueArr = deserializeJSON(serializedKey);
        if (valueArr.len() == 1) return valueArr[1];
        return valueArr;
    }

    // Now check that there aren't any keys in second that weren't
    function diff(any first = '', any second = '', array ignoreKeys = []) {
        var diffs = [];
        if (
            (isSimpleValue(first) && !isSimpleValue(second))
            || (!isSimpleValue(first) && isSimpleValue(second))
        ) {
            diffs.append({
                'path': [],
                'type': 'CHANGE',
                'old': first,
                'new': second
            });
        } else if (isSimpleValue(first) && isSimpleValue(second)) {
            if (
                numericCheck(first)
                && numericCheck(second)
            ) {
                if (precisionEvaluate(first - second) != 0) {
                    diffs.append({
                        'path': [],
                        'type': 'CHANGE',
                        'old': first,
                        'new': second
                    });
                }
            } else if (first != second) {
                diffs.append({
                    'path': [],
                    'type': 'CHANGE',
                    'old': first,
                    'new': second
                });
            }
        } else if (isArray(first) && isArray(second)) {
            for (var i = 1; i <= first.len(); i++) {
                var path = i;

                if (second.len() < i) {
                    diffs.append({
                        'path': [path],
                        'type': 'REMOVE',
                        'old': first[i],
                        'new': ''
                    });
                } else if (isSimpleValue(first[i]) && isSimpleValue(second[i])) {
                    if (
                        numericCheck(first[i])
                        && numericCheck(second[i])
                    ) {
                        if (precisionEvaluate(first[i] - second[i]) != 0) {
                            diffs.append({
                                'path': [path],
                                'type': 'CHANGE',
                                'old': first[i],
                                'new': second[i]
                            });
                        }
                    } else if (first[i] != second[i]) {
                        diffs.append({
                            'path': [path],
                            'type': 'CHANGE',
                            'old': first[i],
                            'new': second[i]
                        });
                    }
                } else {
                    var nestedDiffs = diff(first[i], second[i], ignoreKeys);
                    nestedDiffs = nestedDiffs.each((difference) => {
                        difference.path.prepend(path);
                        diffs.append(difference);
                    });
                }
            }
            for (var t = first.len() + 1; t <= second.len(); t++) {
                var path = t;
                diffs.append({
                    'type': 'ADD',
                    'path': [path],
                    'old': '',
                    'new': second[path]
                });
            }
        } else if (isStruct(first) && isStruct(second)) {
            var keysSeen = {};
            for (var key in first) {
                var path = key;
                if (ignoreKeys.find(key) > 0) {
                    continue;
                }
                if (!first.keyExists(key)) first[key] = '';
                if (!second.keyExists(key)) {
                    diffs.append({
                        'path': [path],
                        'type': 'REMOVE',
                        'old': first[key],
                        'new': ''
                    });
                } else if (isSimpleValue(first[key]) && isSimpleValue(second[key])) {
                    if (
                        numericCheck(first[key])
                        && numericCheck(second[key])
                    ) {
                        if (precisionEvaluate(first[key] - second[key]) != 0) {
                            diffs.append({
                                'key': path,
                                'path': [path],
                                'type': 'CHANGE',
                                'old': first[key],
                                'new': second[key]
                            });
                        }
                    } else if (first[key] != second[key]) {
                        diffs.append({
                            'key': path,
                            'path': [path],
                            'type': 'CHANGE',
                            'old': first[key],
                            'new': second[key]
                        });
                    }
                } else {
                    if (structKeyExists(first, key) && structKeyExists(second, key)) {
                        var nestedDiffs = diff(first[key], second[key], ignoreKeys);
                        nestedDiffs = nestedDiffs.each((difference) => {
                            difference.path.prepend(path);
                            diffs.append(difference);
                        })
                    }
                }
                keysSeen[key] = true;
            }
            // Now check that there aren't any keys in second that weren't
            // in first.
            for (var key2 in second) {
                if (ignoreKeys.find(key2) > 0) {
                    continue;
                };
                if (structKeyExists(second, key2) && !structKeyExists(keysSeen, key2)) {
                    diffs.append({
                        'type': 'ADD',
                        'path': [key2],
                        'old': '',
                        'new': second[key2]
                    });
                }
            }
        }

        return diffs;
    }


    function patch(required original, diff = []) {
        var original = duplicate(arguments.original);
        var diff = duplicate(arguments.diff);
        var diffPatchObj = diffpatch(original, diff);
        return runPatch(diffPatchObj);
    }

    function runPatch(required diffPatchObj) {
        var diffPatchObj = duplicate(arguments.diffPatchObj);
        if (isArray(diffPatchObj)) {
            for (var i = 1; i <= diffPatchObj.len(); i++) {
                diffPatchObj[i] = runPatch(diffPatchObj[i]);
            }
        } else if (isStruct(diffPatchObj)) {
            if (isStruct(diffPatchObj) && diffPatchObj.keyExists('new')) {
                diffPatchObj = diffPatchObj.new;
            } else {
                for (var key in diffPatchObj) {
                    diffPatchObj[key] = runPatch(diffPatchObj[key]);
                }
            }
        }
        return diffPatchObj;
    }

    function displayDiff(required original, diff = []) {
        var original = duplicate(arguments.original);
        var diff = duplicate(arguments.diff);
        var diffPatchObj = diffpatch(original, diff);
        return arrayToList(diffToHTML(diffPatchObj), '');
    }

    function diffToHTML(required diffPatchObj, nodes = []) {
        var diffPatchObj = duplicate(arguments.diffPatchObj);
        if (isArray(diffPatchObj)) {
            nodes.append('<ul>');
            for (var i = 1; i <= diffPatchObj.len(); i++) {
                nodes.append('<li>');
                nodes.append('<span style="font-weight:bold">#i#</span> ');
                nodes = diffToHTML(diffPatchObj[i], nodes);
                nodes.append('</li>');
            }
            nodes.append('</ul>');
        } else if (isStruct(diffPatchObj)) {
            if (isStruct(diffPatchObj) && diffPatchObj.keyExists('new')) {
                if (diffPatchObj.type == 'CHANGE') {
                    nodes.append('<span style="background: ##ffbbbb;text-decoration: line-through;">#diffPatchObj.old#</span> ');
                    nodes.append('<span style="background: ##bbffbb;">#diffPatchObj.new#</span>');
                } else if (diffPatchObj.type == 'ADD') {
                    nodes.append('<span style="background: ##bbffbb;">#diffPatchObj.new#</span>');
                } else if (diffPatchObj.type == 'REMOVE') {
                    nodes.append('<span style="background: ##ffbbbb;text-decoration: line-through;">#diffPatchObj.old#</span>');
                } else {
                    nodes.append('<span style="color:##666">#diffPatchObj.old#</span>');
                }
            } else {
                nodes.append('<ul>');
                for (var key in diffPatchObj) {
                    nodes.append('<li>');
                    nodes.append('<span style="font-weight:bold">#key#</span>: ');
                    nodes = diffToHTML(diffPatchObj[key], nodes);
                    nodes.append('</li>');
                }
                nodes.append('</ul>');
            }
        }
        return nodes;
    }

    function diffpatch(required original, diff = []) {
        var original = duplicate(arguments.original);
        var diff = duplicate(arguments.diff);
        var filterDiffs = diff.reduce((acc, changeItem) => {
            if (changeItem.path.len() == 1) {
                acc.matches[changeItem.path[1]] = {
                    'old': changeItem.old,
                    'new': changeItem.new,
                    'type': changeItem.type
                };
            } else {
                acc.unmatched.append(changeItem);
            }
            return acc;
        }, {matches: {}, unmatched: []});

        var levelDiffs = filterDiffs.matches;


        if (isSimpleValue(original)) {
            if (diff.len()) {
                original = {'old': diff[1].old, 'new': diff[1].new, 'type': diff[1].type};
            } else {
                arguments.original = {'old': original, 'new': original, 'type': 'SAME'}
            }
        } else if (isArray(original)) {
            for (var i = 1; i <= original.len(); i++) {
                var path = i;
                if (isSimpleValue(original[i])) {
                    if (levelDiffs.keyExists(path)) {
                        original[i] = levelDiffs[path];
                        structDelete(levelDiffs, path);
                    } else {
                        original[i] = {'old': original[i], 'new': original[i], 'type': 'SAME'}
                    }
                } else {
                    var subDiffs = filterDiffs.unmatched.reduce((acc, changeItem) => {
                        if (changeItem.path.len() > 1 && changeItem.path[1] == path) {
                            arrayDeleteAt(changeItem.path, 1);
                            acc.append(changeItem);
                        }
                        return acc;
                    }, []);
                    original[i] = diffpatch(original[i], subDiffs);
                }
            }
        } else if (isStruct(original)) {
            for (var key in original) {
                var path = key;
                if (isSimpleValue(original[key])) {
                    if (levelDiffs.keyExists(path)) {
                        original[key] = levelDiffs[path];
                        structDelete(levelDiffs, path);
                    } else {
                        original[key] = {'old': original[key], 'new': original[key], 'type': 'SAME'}
                    }
                } else {
                    var subDiffs = filterDiffs.unmatched.reduce((acc, changeItem) => {
                        if (changeItem.path.len() > 1 && changeItem.path[1] == path) {
                            arrayDeleteAt(changeItem.path, 1);
                            acc.append(changeItem);
                        }
                        return acc;
                    }, []);
                    original[key] = diffpatch(original[key], subDiffs);
                }
            }
        }

        // ADDED Items
        for (var diffKey in levelDiffs) {
            if (isSimpleValue(levelDiffs[diffKey]['new'])) {
                original[diffKey] = levelDiffs[diffKey];
            } else if (isStruct(levelDiffs[diffKey]['new'])) {
                original[diffKey] = {};
                for (var subDiffKey in levelDiffs[diffKey]['new']) {
                    original[diffKey][subDiffKey] = {
                        'old': '',
                        'new': levelDiffs[diffKey]['new'][subDiffKey],
                        'type': 'ADD'
                    }
                }
            } else if (isArray(levelDiffs[diffKey]['new'])) {
                original[diffKey] = {
                    'old': '',
                    'new': levelDiffs[diffKey]['new'],
                    'type': 'ADD'
                }
            }
        }
        return original;
    }

}
