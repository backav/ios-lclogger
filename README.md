## LogCentral ios logger

#### Cocoapods
```
pod 'LCLogger','~>1.3.2'
```

#### 代码示例
```
    LCLogger *log=[LCLogger sessionWithToken:@"#TOKEN#" endpoint:@"http://#logcentral api#"];
    [log log:@"bac你好"];

```
