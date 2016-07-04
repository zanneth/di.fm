//
//  Player.swift
//  di.fm
//
//  Created by Charles Magahern on 4/26/16.
//

import AVFoundation
import Foundation

protocol PlayerDelegate: class
{
    func playerDidStartPlayingChannel(player: Player, channel: Channel)
    func playerDidPausePlayback(player: Player)
    func playerDidStopPlayback(player: Player)
    func playerCurrentTrackDidChange(player: Player, newTrack: Track?)
}

class Player : NSObject
{
    var listenKey:                  String?
    var streamSet:                  StreamSet?
    weak var delegate:              PlayerDelegate?
    weak var streamDelegate:        AudioStreamDelegate?
    
    private var _player:            AVPlayer?
    private var _playerItem:        AVPlayerItem?
    private var _streamer:          AudioStreamer?
    private var _errorStream:       StandardErrorOutputStream = StandardErrorOutputStream()
    
    private let _playerItemKeyPaths = ["timedMetadata", "tracks"]
    
    var currentChannel: Channel?
    {
        didSet
        {
            self.currentTrack = nil
            _reloadStream()
        }
    }
    
    private(set) var currentTrack: Track?
    {
        didSet
        {
            self.delegate?.playerCurrentTrackDidChange(self, newTrack: nil)
        }
    }
    
    func play()
    {
        do {
            try AVAudioSession.sharedInstance().setCategory(AVAudioSessionCategoryPlayback)
        }
        catch let error as NSError {
            _logError("error setting audio category", error: error)
        }
        
        _streamer?.start()
        
        if (self.currentChannel != nil) {
            self.delegate?.playerDidStartPlayingChannel(self, channel: self.currentChannel!)
        }
    }
    
    func pause()
    {
        if let streamer = _streamer {
            if (streamer.isPlaying()) {
                _streamer?.stop()
                self.delegate?.playerDidPausePlayback(self)
            }
        }
    }
    
    func isPlaying() -> Bool
    {
        var playing: Bool = false
        if let streamer = _streamer {
            playing = streamer.isPlaying()
        }
        return playing
    }
    
    // MARK: KVO
    
    override func observeValueForKeyPath(keyPath: String?,
                                         ofObject object: AnyObject?,
                                                  change: [String : AnyObject]?,
                                                  context: UnsafeMutablePointer<Void>)
    {
        var newTrack: Track? = nil
        
        if let keyPath = keyPath {
            if let playerItem = object as? AVPlayerItem {
                if (keyPath == "timedMetadata") {
                    newTrack = Track(playerItem)
                } else if (keyPath == "tracks") {
                    for track in playerItem.tracks {
                        if (track.assetTrack.mediaType == AVMediaTypeAudio) {
                            print("disabling audio track \(track)")
                            track.enabled = false
                        }
                    }
                }
            }
        }
        
        self.currentTrack = newTrack
    }
    
    // MARK: Internal
    
    internal func _cachedChannelStream(channel: Channel) -> Stream?
    {
        var stream: Stream? = nil
        
        if (self.streamSet != nil) {
            let streamlist = self.streamSet?.streamlist
            let streams = streamlist?.channelIDToStreams[channel.identifier]
            if (streams?.count > 0) {
                stream = streams?.first
            }
        } else {
            _logError("No stream set initialized on player.", error: nil)
        }
        
        return stream
    }
    
    internal func _reloadStream()
    {
        var newPlayer: AVPlayer? = nil
        var newPlayerItem: AVPlayerItem? = nil
        var newStreamer: AudioStreamer? = nil
        
        // create player item and player for new channel stream
        if (self.currentChannel != nil) {
            if let stream = _cachedChannelStream(self.currentChannel!) {
                let streamURLComponents = NSURLComponents(URL: stream.url, resolvingAgainstBaseURL: false)!
                if (self.listenKey != nil) {
                    streamURLComponents.query = "?\(self.listenKey!)"
                }
                
                if let streamURL = streamURLComponents.URL {
                    newPlayerItem = AVPlayerItem(URL: streamURL)
                    newPlayer = AVPlayer(playerItem: newPlayerItem!)
                    newStreamer = AudioStreamer(URL: streamURL)
                } else {
                    _logError("Could not parse URL using components: \(streamURLComponents)", error: nil)
                }
            } else {
                _logError("No stream found for channel \(self.currentChannel!.name)", error: nil)
            }
        } else {
            self.delegate?.playerDidStopPlayback(self)
        }
        
        // reset playback state
        let prevPlaying = self.isPlaying()
        self.pause()
        
        // setup observer
        for keyPath in _playerItemKeyPaths {
            _playerItem?.removeObserver(self, forKeyPath: keyPath)
            newPlayerItem?.addObserver(self, forKeyPath: keyPath, options: NSKeyValueObservingOptions(), context: nil)
        }
        
        // save new streaming objects
        _streamer = newStreamer
        _streamer?.delegate = self.streamDelegate
        _player = newPlayer
        _player?.play()
        _playerItem = newPlayerItem
        
        // begin playback if necessary
        if (prevPlaying) {
            self.play()
        }
    }
    
    internal func _logError(description: String, error: NSError?)
    {
        print("ERROR: \(description) \(error)", toStream: &_errorStream)
    }
}
