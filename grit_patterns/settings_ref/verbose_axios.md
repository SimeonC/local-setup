---
title: Consistently use axios
level: error
---

tags: #cleanup

```grit
or {
    and { `await axios<$type>($props)`, $axios = `await axios`, $type_final = raw`<$type>` },
    and { `axios<$type>($props)`, $axios = `axios`, $type_final = raw`<$type>` },
    and { `axios($props)`, $axios = `axios`, $type_final = raw`` }
} where {
    $args = [],
    $pairs = [],
    $method = "get",
    $props <: contains bubble($props, $pairs, $args, $method, $url) pair() as $p where or {
        $p <: contains `url: $url`,
        $p <: contains `method: '$m'` where {
            $method = $m
        },
        $p <: contains `data: $data` where {
            $props <: contains `method: '$method'` where {
                $method <: contains or { r"put", r"post", r"patch" }
            },
            $args += $data,
        },
        $pairs += $p
    },
    $method = lowercase($method),
    $pairs = join($pairs, ", "),
    $args += `{ $pairs }`,
    $args = join($args, ", ")
} => `$axios.$method$type_final($url, $args)`
```

## Rewrites the config format to shorthand for get

```ts
const r = await axios({
  method: 'get',
  url: '/some-url',
  otherProp: true,
});
const r2 = await axios<SomeType>({
  method: 'GET',
  url: '/some-url',
  otherProp: true,
});
```

```ts
const r = await axios.get('/some-url', { otherProp: true });
const r2 = await axios.get<SomeType>('/some-url', { otherProp: true });
```

## Rewrites the config format to shorthand for PUT

```ts
const r = await axios({
  method: 'put',
  url: '/some-url',
  otherProp: true,
  data: someData,
});
```

```ts
const r = await axios.put('/some-url', someData, { otherProp: true });
```
